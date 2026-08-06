class CategorizeEventJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(event)
    profile = event.auto_sort_profile
    return unless profile
    return if event.sections.any? # the user tagged it themselves — don't second-guess

    result = Events::Categorize.new(event: event, profile: profile).call
    event.sections = result.sections
    # Quick-added events are all-day until a time is known; times the user
    # set themselves (all_day already false) are never touched.
    if event.all_day? && result.starts_at
      event.update!(starts_at: result.starts_at, ends_at: result.ends_at, all_day: false)
    end
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Best-effort: once the model is out of chances the event just stays
    # unsorted, and the user can tag it from the edit form.
    record_failure(e, user: event.user, context: { event_id: event.id })
  end
end
