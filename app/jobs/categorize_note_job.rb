class CategorizeNoteJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(note)
    profile = note.auto_sort_profile
    return unless profile
    return if note.sections.any? # the user tagged it themselves — don't second-guess

    result = Notes::Categorize.new(note: note, profile: profile).call
    note.sections = result.sections
    note.update!(title: result.title) if note.title.blank? && result.title.present?
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Best-effort: once the model is out of chances the note just stays
    # unfiled, and the user can title and tag it from the edit form.
    record_failure(e, user: note.user, context: { note_id: note.id })
  end
end
