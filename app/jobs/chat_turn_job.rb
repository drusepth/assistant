# One assistant reply in a chat-kind tool run (D22). A failed turn appends
# a notice — the app speaking, never sent to the model — so the transcript
# shows what happened and the thinking indicator can't stick; the run
# itself is never poisoned.
class ChatTurnJob < ApplicationJob
  queue_as :default

  def perform(run)
    run.tool.new(run).reply!
  rescue Llm::Error => e
    run.tool_run_messages.create!(role: :notice, content: "#{e.message} Your message is still here — send another to retry.")
  rescue StandardError
    run.tool_run_messages.create!(role: :notice, content: "Something unexpected went wrong — send another message to retry.")
    raise
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to(run) if run&.persisted?
  end
end
