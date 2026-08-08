# "Save a recap" on a chat-kind run (D29): the one wrap-up LLM call that
# lands a filed Note — the only primitive a chat produces, and what gives
# the next session its memory. Same no-retry policy as ChatTurnJob: the
# user is on the page, and clicking the button again is the retry.
class ChatRecapJob < ApplicationJob
  queue_as :default

  def perform(run)
    run.tool.new(run).recap!
  rescue Llm::Error => e
    run.tool_run_messages.create!(role: :notice, content: e.message)
    AppError.record(e, source: self.class.name, user: run.user, context: { tool_run_id: run.id })
  rescue StandardError => e
    run.tool_run_messages.create!(role: :notice, content: "Something unexpected went wrong saving the recap — try again.")
    AppError.record(e, source: self.class.name, user: run.user, context: { tool_run_id: run.id })
    raise
  ensure
    if run&.persisted?
      run.update_column(:recap_requested_at, nil)
      Turbo::StreamsChannel.broadcast_refresh_to(run)
    end
  end
end
