class ToolRunJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(run)
    run.update!(status: :running)
    # Same switch the agent's preparation uses: the landing helpers write
    # intents rather than rows (D-tool-run-offers).
    run.preparing = run.tool.kind == :draft
    tool = run.tool.new(run)
    tool.call
    run.update!(status: :done, output: run.output.merge(staged_output(tool)))
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

  private
    # A draft run keeps what it would create on the run itself (D-tool-run-offers):
    # the note and its follow-ups are offers on the run page, each with its own
    # Add button, and none of it is in the user's notes, tasks or calendar until
    # that click.
    def staged_output(tool)
      tool.landings.any? ? { "landings" => tool.landings } : {}
    end
end
