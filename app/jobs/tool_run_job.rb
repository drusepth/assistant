class ToolRunJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(run)
    run.update!(status: :running)
    run.tool.new(run).call
    run.update!(status: :done)
  rescue Llm::Error => e
    # The run stays "running" while attempts remain, so the live page shows
    # honest progress instead of a failure the next attempt may clear.
    raise if will_retry?(e)

    run.update!(status: :failed, error: e.message)
    record_failure(e, user: run.user, context: { tool_run_id: run.id, tool_slug: run.tool_slug })
  rescue StandardError => e
    # Never leave a run spinning: mark it failed with a generic message,
    # then let the real error surface in the job backend.
    run.update!(status: :failed, error: "Something unexpected went wrong — try again.")
    record_failure(e, user: run.user, context: { tool_run_id: run.id, tool_slug: run.tool_slug })
    raise
  ensure
    # The run page subscribes to the run and refreshes itself.
    Turbo::StreamsChannel.broadcast_refresh_to(run) if run&.persisted?
  end
end
