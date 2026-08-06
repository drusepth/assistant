class AnalyzeDocumentJob < ApplicationJob
  queue_as :default

  def perform(document)
    profile = document.analyzable_profile
    return unless profile

    document.update!(analysis_status: :processing)
    result = Documents::Analyze.new(document: document, profile: profile).call
    document.update!(
      summary: result.summary,
      extracted_text: result.extracted_text,
      suggested_sections: result.section_slugs,
      analysis_status: :analyzed,
      analysis_error: nil
    )
    # Untagged documents get filed automatically (D16); once the user has
    # tagged a document themselves, suggestions stay suggest-and-click.
    document.sections = document.suggested_section_records if document.sections.none?
  rescue Llm::Error, Documents::Analyze::UnsupportedFileType => e
    document.update!(analysis_status: :failed, analysis_error: e.message)
    AppError.record(e, source: self.class.name, user: document.user, context: { document_id: document.id })
  rescue StandardError => e
    # A bug, not a user-facing condition: don't leave the document stuck in
    # "processing", but let the error propagate to the job backend's log.
    document.update!(analysis_status: :failed, analysis_error: "Something went wrong during analysis — try again.")
    AppError.record(e, source: self.class.name, user: document.user, context: { document_id: document.id })
    raise
  end
end
