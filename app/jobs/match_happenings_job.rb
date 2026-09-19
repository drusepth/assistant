# Reads the listings a source just delivered and marks the ones that are
# for this person (D-event-radar). In a job rather than the refresh: a
# publisher's poll must not wait on a provider, and the row is already in
# the river — matching only decides whether it also earns a chip and a nudge.
#
# Idempotent and self-limiting: `matched_at` marks a row read whether or not
# anything came of it, so two runs racing find nothing to do.
class MatchHappeningsJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(user)
    Radar::Match.call(user)
  rescue Llm::Error => e
    raise if will_retry?(e)

    record_failure(e, user: user)
  end
end
