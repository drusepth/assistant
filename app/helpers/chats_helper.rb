# The conversation index (D-chat-index).
module ChatsHelper
  # A chat tool wears its section's identity colour, the way everything else
  # in the app does. `task_chat` is sectionless on purpose (D30 — it belongs
  # to a task, not a life area), so it falls back to a neutral dot.
  def chat_dot_classes(tool)
    section = tool.section_records.first
    section ? section_dot_classes(section) : "bg-stone-400"
  end

  # The preview line: the newest turn, said by whoever said it. A conversation
  # whose opening reply is still being written has nothing to preview yet and
  # says so rather than showing a blank row.
  def chat_preview(conversation)
    message = conversation.last_message
    return "Starting…" if message.nil?

    prefix = message.user_role? ? "You: " : ""
    "#{prefix}#{message.content.squish}"
  end
end
