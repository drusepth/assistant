class AnalyzeDocumentJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(document)
    profile = document.analyzable_profile
    return unless profile

    document.update!(analysis_status: :processing)
    result = Documents::Analyze.new(document: document, profile: profile).call
    document.update!(
      summary: result.summary,
      extracted_text: result.extracted_text,
      extracted_facts: result.facts,
      suggested_sections: result.section_slugs,
      # What the document proposes (D-document-intake): waits on the
      # review page; nothing below lands a row.
      landings: document.merge_landings(result.landings),
      # A title the reader chose beats "IMG 4032" and never beats one a
      # person typed (D16).
      title: document.filename_titled? && result.title ? result.title : document.title,
      # Whether this is a health plan is a fact about the document itself,
      # so it is filed like its sections (D16): set by the reader when the
      # owner hasn't said, never over the owner's own pin (HEALTH.md §4).
      # This is what retires Health::Coverage's keyword match for analyzed
      # documents (D-no-keyword-logic).
      health_plan: document.health_plan.nil? ? result.health_plan : document.health_plan,
      analysis_status: :analyzed,
      analysis_error: nil
    )
    # Untagged documents get filed automatically (D16); once the user has
    # tagged a document themselves, suggestions stay suggest-and-click.
    document.sections = document.suggested_section_records if document.sections.none?
    record_comp_change(document)
  rescue Llm::Error, Documents::Read::Unreadable => e
    # A retry is coming: leave the document showing "processing" rather than
    # flashing a failure the next attempt may well clear. (An unreadable file
    # is never transient, so it lands here on the first pass.)
    raise if will_retry?(e)

    document.update!(analysis_status: :failed, analysis_error: e.message)
    record_failure(e, user: document.user, context: { document_id: document.id })
  rescue StandardError => e
    # A bug, not a user-facing condition: don't leave the document stuck in
    # "processing", but let the error propagate to the job backend's log.
    document.update!(analysis_status: :failed, analysis_error: "Something went wrong during analysis — try again.")
    record_failure(e, user: document.user, context: { document_id: document.id })
    raise
  end

  private
    # A rate change against the previous stub lands on the comp timeline
    # (D-career-signal). The analysis itself succeeded — a timeline hiccup is recorded,
    # never surfaced as a failed document.
    def record_comp_change(document)
      Career::RecordCompChange.new(document).call
    rescue StandardError => e
      record_failure(e, user: document.user, context: { document_id: document.id })
    end
end
