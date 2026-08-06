class CategorizeNoteJob < ApplicationJob
  queue_as :default

  def perform(note)
    profile = note.auto_sort_profile
    return unless profile
    return if note.sections.any? # the user tagged it themselves — don't second-guess

    result = Notes::Categorize.new(note: note, profile: profile).call
    note.sections = result.sections
    note.update!(title: result.title) if note.title.blank? && result.title.present?
  rescue Llm::Error
    # Best-effort: an unreachable or misbehaving model just leaves the note
    # unfiled, and the user can title and tag it from the edit form.
  end
end
