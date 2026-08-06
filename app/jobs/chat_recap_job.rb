# "Save a recap" on a chat-kind run (D22): the one wrap-up LLM call that
# lands a filed Note — the only primitive a chat produces, and what gives
# the next session its memory.
class ChatRecapJob < ApplicationJob
  queue_as :default

  def perform(run)
    run.tool.new(run).recap!
  rescue Llm::Error => e
    run.tool_run_messages.create!(role: :notice, content: e.message)
  rescue StandardError
    run.tool_run_messages.create!(role: :notice, content: "Something unexpected went wrong saving the recap — try again.")
    raise
  ensure
    Turbo::StreamsChannel.broadcast_refresh_to(run) if run&.persisted?
  end
end
