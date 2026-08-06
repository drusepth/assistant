class Document < ApplicationRecord
  include Visible
  include Sectionable

  has_one_attached :file

  validates :title, presence: true

  # Quick capture is just the file — the title falls back to its name (D16).
  before_validation :default_title_from_filename, on: :create

  # nil analysis_status = never analyzed (or no model configured yet).
  enum :analysis_status, {
    queued: "queued", processing: "processing", analyzed: "analyzed", failed: "failed"
  }, prefix: :analysis

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

  private
    def default_title_from_filename
      return if title.present? || !file.attached?

      self.title = file.filename.base.to_s.tr("-_", " ").squeeze(" ").strip.upcase_first
    end
end
