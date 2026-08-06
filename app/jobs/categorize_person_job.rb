class CategorizePersonJob < ApplicationJob
  queue_as :default

  def perform(person)
    profile = person.auto_sort_profile
    return unless profile
    return if person.sections.any? # the user tagged them themselves — don't second-guess

    result = People::Categorize.new(person: person, profile: profile).call
    person.sections = result.sections
    person.update!(relationship: result.relationship) if person.relationship.blank? && result.relationship.present?
  rescue Llm::Error => e
    # Best-effort: an unreachable or misbehaving model just leaves the person
    # unfiled, and the user can tag them from the edit form.
    AppError.record(e, source: self.class.name, user: person.user, context: { person_id: person.id })
  end
end
