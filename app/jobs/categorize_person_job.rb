class CategorizePersonJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(person)
    profile = person.auto_sort_profile
    return unless profile
    return if person.sections.any? # the user tagged them themselves — don't second-guess

    result = People::Categorize.new(person: person, profile: profile).call
    person.sections = result.sections
    person.update!(relationship: result.relationship) if person.relationship.blank? && result.relationship.present?
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Best-effort: once the model is out of chances the person just stays
    # unfiled, and the user can tag them from the edit form.
    record_failure(e, user: person.user, context: { person_id: person.id })
  end
end
