# Drafts one of the radar's two sentences (D-event-radar §5.1) — asked for
# out loud, in a job, and only ever filling a blank.
class AuthorRadarBriefJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(user, kind)
    Radar::Briefs.call(user, kind)
  rescue Llm::Error => e
    raise if will_retry?(e)

    record_failure(e, user: user, context: { kind: kind })
  end
end
