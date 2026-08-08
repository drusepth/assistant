module Tool
  # Rehearsal for the real thing (docs/CAREER.md §3.1): the model plays the
  # interviewer, one question at a time, and coaches after each answer —
  # naming where a tracked win would have made the answer stronger, which is
  # the owned-memory moat at work. Chat kind (D29), tutor pattern: recaps
  # are what the next session (and the prep tool) read.
  class MockInterview < ChatBase
    self.title = "Mock interview"
    self.description = "Practice out loud with an interviewer who coaches every answer — and remembers last time."
    self.section_slugs = %w[ career ]
    self.quick_replies = [
      "Ask me the next question",
      "How was that answer?",
      "Make it harder",
      "Switch interviewer style"
    ]

    input :focus, required: true,
      label: "What interview are we practicing for?",
      hint: "“Warehouse shift lead at Acme”, “first nursing job”."
    input :persona,
      label: "Who's interviewing?",
      hint: "Optional — “a skeptical operations manager”, “a friendly HR screen”."

    BEHAVIOR = <<~PROMPT.freeze
      You are the mock-interview feature of a private, self-hosted life
      assistant, role-playing the interviewer for the stated role. Rules of the
      room:
      - One question at a time, and wait for the answer.
      - After each answer, step briefly out of character to coach: one thing
        that landed, one thing to tighten, and — when the user's tracked record
        holds a stronger example — name it ("your logged win about the
        inventory audit fits this question better").
      - Then back in character with the next question. Mix formats: opener,
        behavioral, role-specific, the uncomfortable one ("why did you leave?").
      - Match difficulty to how the user is doing; harder on request.
      - Stay realistic for the stated role and interviewer persona; switch
        personas when asked.
      - Short conversational turns, plain text only — no markdown tables, no
        bullet-point lectures.
      - Never invent facts about the company; the interview is practice for
        answering, not a source of company information.
    PROMPT

    private
      def system_prompt
        parts = [ BEHAVIOR ]
        parts << "The interview being practiced: #{inputs[:focus]}"
        parts << "Interviewer persona: #{inputs[:persona]}" if inputs[:persona].present?
        context = section_context
        unless context.empty?
          parts << "The user's tracked career record — prep sheets, logged wins, work history, past mock-interview recaps. Coach from it:\n#{context.to_prompt}"
        end
        parts.join("\n\n")
      end

      def opening_instruction
        "Open the session: one sentence of scene-setting as the interviewer (who you are, what the interview is), then ask the first question. If a past recap says what needed polish, start there."
      end

      def recap_instruction
        <<~TEXT
          The session is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: which questions we practiced, what's working, and the two
          or three concrete things to polish before the real interview —
          written for the user to reread the night before. The title like
          "Mock interview recap — <role>".
        TEXT
      end

      def recap_fallback_title = "Mock interview recap — #{inputs[:focus]}"
  end
end
