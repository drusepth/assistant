module Tool
  # The homework-tonight door (docs/EDUCATION_PLAN.md §6), deliberately
  # outside the curriculum spine: paste anything — the worksheet question,
  # the confusing paragraph — and get it explained at your level, Socratic
  # rules in force. No subject required; the recap files to Education like
  # every session, and can suggest planting the topic in a syllabus.
  class ExplainThis < ChatBase
    self.title = "Explain this"
    self.description = "Paste the question or the paragraph — get it explained at your level, never just done for you."
    self.section_slugs = %w[ education ]
    self.quick_replies = [
      "Simpler, please",
      "Show me a worked example",
      "Why does that work?",
      "Let me try one"
    ]

    input :puzzle, kind: :textarea, required: true,
      label: "What needs explaining?",
      hint: "The homework question, the letter's paragraph, the error message — paste it as it is."
    input :learner,
      label: "Who's asking?",
      hint: "Optional — “me”, “my 9-year-old”. It sets the level."

    BEHAVIOR = <<~PROMPT.freeze
      You are the explain-anything feature of a private, self-hosted life
      assistant. Someone pasted a thing they don't get; your job is that they
      *do* get it, not that it gets done. Rules of the room:
      - Start from what they can see: name what kind of thing this is, then ask
        one question to find where their understanding stops.
      - Homework gets guided, never answered outright: lead them to produce the
        answer themselves, step by step.
      - Adapt to the learner; for a child, short sentences and concrete examples.
      - Short turns, one idea then a question. Plain conversational text — no
        markdown tables, no LaTeX.
      - If it's genuinely beyond a chat (a legal notice, a medical result), say
        so and name the better door rather than improvising expertise.
    PROMPT

    private
      def system_prompt
        parts = [ BEHAVIOR, "What they pasted:\n#{inputs[:puzzle]}" ]
        parts << "The learner: #{inputs[:learner]}" if inputs[:learner].present?
        parts.join("\n\n")
      end

      def opening_instruction
        "Open the session: one sentence on what this thing is, then your first question to find where their understanding stops."
      end

      def recap_instruction
        <<~TEXT
          The session is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: what the thing was, the idea that unlocked it, and one
          practice suggestion — short, written for the learner to reread. If this
          clearly belongs to a school subject, end with one line suggesting they
          plant it in their syllabus with Learn something.
        TEXT
      end

      def recap_fallback_title = "Explained — #{inputs[:puzzle].to_s.truncate(40)}"
  end
end
