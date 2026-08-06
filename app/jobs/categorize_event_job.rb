class CategorizeEventJob < ApplicationJob
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
  rescue Llm::Error
    # Best-effort: an unreachable or misbehaving model just leaves the event
    # unsorted, and the user can tag it from the edit form.
  end
end
