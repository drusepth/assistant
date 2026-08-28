# Runs one suggestion's tool ahead of the click (D-agent-prepared-work).
# One job per suggestion rather than a loop inside AgentScanJob: a model
# call takes as long as a model takes, and three of them must not decide how
# long the deterministic scan blocks the queue.
#
# Deliberately no RetriesModelCalls. Every other model call in the app is
# answering something the user asked for, so retrying a transient failure is
# owed to them; this one is speculative, and spending a second round of
# unbidden tokens to rescue a draft nobody has asked to see is exactly the
# budget discipline this feature is gated by. A failure leaves the
# suggestion as the prefilled redirect it already was.
class AgentPrepareJob < ApplicationJob
  queue_as :default

  def perform(suggestion)
    Agent::Prepare.new(suggestion).call
  rescue StandardError => e
    # Silent for the user — but not for whoever runs the box (D23).
    record_failure(e, user: suggestion.user,
      context: { prepare: suggestion.watcher_slug, suggestion: suggestion.id })
    nil
  end
end
