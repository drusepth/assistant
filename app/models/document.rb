class Document < ApplicationRecord
  include Visible
  include Sectionable

  has_one_attached :file

  # The rows this document produced (D-document-intake). The join goes with
  # the document; the rows stay.
  has_many :document_items, dependent: :destroy

  validates :title, presence: true

  # Quick capture is just the file — the title falls back to its name (D16).
  before_validation :default_title_from_filename, on: :create

  # nil analysis_status = never analyzed (or no model configured yet).
  enum :analysis_status, {
    queued: "queued", processing: "processing", analyzed: "analyzed", failed: "failed"
  }, prefix: :analysis

  # A photographed or scanned document shows its picture on its page; a
  # PDF or text file shows its facts. Delegated to the blob so a document
  # with no file answers false rather than raising.
  def image? = file.attached? && file.image?

  def analyzable_profile
    profile = user.household.model_profile
    profile if profile&.configured?
  end

  def enqueue_analysis!
    update!(analysis_status: :queued, analysis_error: nil)
    AnalyzeDocumentJob.perform_later(self)
  end

  def suggested_section_records
    Section.where(slug: suggested_sections).order(:parent_id, :position) - sections
  end

  # ── Landings (D-document-intake) ─────────────────────────────────────

  def proposed_landings = landings.select { |entry| entry["status"] == "proposed" }
  def skipped_landings = landings.select { |entry| entry["status"] == "skipped" }
  def saved_landings = landings.select { |entry| entry["status"] == "saved" }
  def landings_to_review? = proposed_landings.any?

  # Every entry as a review-page Draft, index preserved so a submission can
  # name it. Duplicate flags are computed here, at read time, against the
  # rows the viewer can see now.
  def landing_drafts(context)
    landings.each_with_index.filter_map do |entry, index|
      kind = Landing.find(entry["kind"]) or next

      landing = kind.new(context)
      flags = entry["status"] == "proposed" && landing.duplicate_of(entry["attributes"]) ? [ "duplicate" ] : []
      Landing::Draft.new(kind: kind.kind, attributes: entry["attributes"], index: index, keep: flags.empty?,
        fingerprint: entry["fingerprint"], status: entry["status"], flags: flags)
    end
  end

  # New proposals join the existing entries: anything already saved or
  # skipped keeps its status (a fingerprint the user has ruled on is never
  # re-proposed), the rest is replaced by this analysis.
  def merge_landings(proposed)
    settled = landings.reject { |entry| entry["status"] == "proposed" }
    settled_fingerprints = settled.map { |entry| entry["fingerprint"] }
    settled + proposed.reject { |entry| settled_fingerprints.include?(entry["fingerprint"]) }
  end

  # The document is still titled by its file name — the D16 case where a
  # better title from the reader may replace it without overwriting
  # anything a person typed.
  def filename_titled?
    file.attached? && title == title_from_filename
  end

  # The rows already saved from this document, newest first.
  def produced_items
    document_items.includes(:item).order(:id).map(&:item).compact
  end

  private
    def default_title_from_filename
      return if title.present? || !file.attached?

      self.title = title_from_filename
    end

    def title_from_filename
      file.filename.base.to_s.tr("-_", " ").squeeze(" ").strip.upcase_first
    end
end
