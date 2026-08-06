# One assistant reply in a chat-kind tool run (D29). Deliberately not
# RetriesModelCalls: mid-conversation, a visible notice the user can retry
# by just typing again beats minutes of silent background retries. A failed
# turn appends that notice — the app speaking, never sent to the model — so
# the transcript shows what happened, the thinking indicator can't stick,
# and the run itself is never poisoned.
class ChatTurnJob < ApplicationJob
  queue_as :default

  def perform(run)
    run.tool.new(run).reply!
  rescue Llm::Error => e
    run.tool_run_messages.create!(role: :notice, content: "#{e.message} Your message is still here — send another to retry.")
    AppError.record(e, source: self.class.name, user: run.user, context: { tool_run_id: run.id })
  rescue StandardError => e
    run.tool_run_messages.create!(role: :notice, content: "Something unexpected went wrong — send another message to retry.")
    AppError.record(e, source: self.class.name, user: run.user, context: { tool_run_id: run.id })
    raise
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to(run) if run&.persisted?
  end
end
