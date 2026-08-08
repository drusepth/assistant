module Tool
  # The chat tool kind (D29): a conversation, not a one-shot pipeline,
  # riding the whole run lifecycle — Act-zone card, run page (which doubles
  # as the chat surface), history. Three verbs:
  #
  #   call    — ToolRunJob's entry: generate the opening assistant message
  #             from owned context, then the run is `done`, which for a chat
  #             means *live* — the composer stays open.
  #   reply!  — ChatTurnJob's entry: one assistant reply to the transcript.
  #   recap!  — ChatRecapJob's entry: the only way a chat produces a
  #             primitive (D20 — no auto-writes): one wrap-up call landing a
  #             filed Note, recorded on the run like any draft.
  #
  # The model sees the system prompt plus the last TRANSCRIPT_WINDOW
  # conversational turns — lean on purpose, small local models included
  # (the Tier-A constraint). Notices (the app's own retry hints) are never
  # sent to the model.
  class ChatBase < Base
    self.kind = :chat

    # One-tap turns the composer offers as chips — a chat tool declares the
    # short prompts its audience reaches for ("Quiz me"); empty means none.
    class_attribute :quick_replies, instance_accessor: false, default: []

    TRANSCRIPT_WINDOW = 30

    def call
      append_assistant(chat_text(opening_messages))
    end

    def reply!
      append_assistant(chat_text(conversation_messages))
    end

    def recap!
      response = profile.client.chat(recap_messages, json: true)
      body = response.dig("recap", "body")
      raise Llm::Error, "The model couldn't write a recap — try again." if body.blank?

      create_note(
        title: response.dig("recap", "title").presence || recap_fallback_title,
        body: body
      )
    end

    private
      def chat_text(messages)
        content = profile.client.chat(messages)
        raise Llm::Error, "The model returned an empty reply — try again." if content.blank?

        content
      end

      def append_assistant(content)
        run.tool_run_messages.create!(role: :assistant, content: content)
      end

      def transcript
        run.tool_run_messages.conversational.ordered.last(TRANSCRIPT_WINDOW)
      end

      def conversation_messages
        [ { role: "system", content: system_prompt } ] +
          transcript.map { |message| { role: message.role, content: message.content } }
      end

      def opening_messages
        [
          { role: "system", content: system_prompt },
          { role: "user", content: opening_instruction }
        ]
      end

      def recap_messages
        conversation_messages + [ { role: "user", content: recap_instruction } ]
      end

      # Subclasses say who they are and how sessions open and close.
      def system_prompt = raise(NotImplementedError)
      def opening_instruction = raise(NotImplementedError)
      def recap_instruction = raise(NotImplementedError)
      def recap_fallback_title = "Recap — #{self.class.title}"
  end
end
