module Tool
  # The task page's conversation (D30). Plenty of tasks are mental work —
  # decide, brainstorm, draft — that can be *done* in a chat, so every task
  # page can host one. Sectionless on purpose: the entry point is the task
  # page, never an Act zone, and the run binds to its task through
  # tool_runs.subject rather than a form input.
  #
  # The opening costs nothing: Tasks::ConversationsController creates the
  # run already `done`, seeded with the task's capture-time guiding
  # questions as assistant turns — the first model call is the reply to the
  # user's first message. `call` therefore never runs.
  #
  # The recap verb is repurposed (same button, same job): instead of filing
  # a Note it distills the conversation into the task's answer —
  # tasks.resolution, the durable outcome the user keeps.
  class TaskChat < ChatBase
    self.title = "Talk it through"
    self.description = "Work on a task in conversation — think, decide, draft, and land on an answer."
    self.section_slugs = []
    self.hosted_on_subject = true
    self.quick_replies = [
      "Help me get started",
      "Give me a few options to pick from",
      "What would you suggest?",
      "Draft an answer for me"
    ]

    def self.recap_button_label(run)
      run.subject&.resolution.present? ? "Update the saved answer" : "Save as the answer"
    end

    def self.recap_pending_label = "Saving the answer…"

    def self.recap_hint
      "Landed on something? Save it as this task's answer — it stays on the task."
    end

    BEHAVIOR = <<~PROMPT.freeze
      You are the task assistant of a private, self-hosted life assistant, in
      conversation about one specific task. Many tasks are mental work —
      deciding, brainstorming, drafting, planning — and your job is to move
      this one forward right here in the chat, not to describe how the user
      might do it somewhere else.
      - Do the thinking with them: offer concrete options, examples, and
        drafts, then sharpen them with the user's reactions.
      - Short turns — a dialogue, not a lecture. One idea, then a question.
        Plain conversational text only: no markdown tables, no LaTeX.
      - Stay on this task; steer back gently when things drift.
      - When the conversation lands on a decision, list, or draft, offer to
        save it as the task's answer — the user has a button for that.
    PROMPT

    def call
      raise NotImplementedError, "task chats open from stored questions, not a model call"
    end

    def recap!
      response = profile.client.chat(recap_messages, json: true)
      body = response.dig("answer", "body")
      raise Llm::Error, "The model couldn't distill an answer — try again." if body.blank?

      task.update!(resolution: body)
      run.tool_run_messages.create!(role: :notice, content: "Saved as the task's answer.")
    end

    private
      def task
        run.subject or raise Llm::Error, "This conversation's task is gone."
      end

      def system_prompt
        [ BEHAVIOR, task_block ].join("\n\n")
      end

      def task_block
        parts = [ "The task: #{task.title}" ]
        parts << "Notes on the task: #{task.notes}" if task.notes.present?
        parts << "Due: #{task.due_on.iso8601}" if task.due_on
        if (goal = task.goal)
          steps = goal.tasks.order(:created_at, :id).map do |step|
            "- #{step.title}#{" (done)" if step.completed?}#{" ← this task" if step == task}"
          end
          parts << "It is a step of the goal “#{goal.title}”, alongside:\n#{steps.join("\n")}"
        end
        parts << "The answer saved on the task so far:\n#{task.resolution}" if task.resolution.present?
        parts.join("\n")
      end

      def recap_instruction
        <<~TEXT
          The user wants to save this conversation's outcome onto the task.
          Respond with a JSON object {"answer": {"body": "..."}}.
          The body is the answer itself — the decision, list, draft, or plan
          the conversation arrived at — concrete, complete, and written to
          stand alone when reread later. It is not a summary of the chat;
          leave out the back-and-forth.
        TEXT
      end

      def opening_instruction
        raise NotImplementedError, "task chats open from stored questions, not a model call"
      end
  end
end
