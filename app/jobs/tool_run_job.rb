class ToolRunJob < ApplicationJob
  queue_as :default

  def perform(run)
    run.update!(status: :running)
    run.tool.new(run).call
    run.update!(status: :done)
  rescue Llm::Error => e
    run.update!(status: :failed, error: e.message)
  rescue StandardError
    # Never leave a run spinning: mark it failed with a generic message,
    # then let the real error surface in the job backend.
    run.update!(status: :failed, error: "Something unexpected went wrong — try again.")
    raise
  ensure
    # The run page subscribes to the run and refreshes itself.
    Turbo::StreamsChannel.broadcast_refresh_to(run) if run&.persisted?
  end
end
