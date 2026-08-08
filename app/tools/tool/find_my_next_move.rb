module Tool
  # The guidance counselor the 99% never had (docs/CAREER.md §3.6). A chat
  # whose context spans Career + Hobbies + Education — the cross-referencing
  # dividend: it sees the warehouse job, the PC-building hobby, and the
  # finished learning goals at once, and explores from what's actually
  # there. Honest about anything current: wages and local demand are named
  # as things to verify, never asserted.
  class FindMyNextMove < ChatBase
    self.title = "Find my next move"
    self.description = "A career conversation that knows your work, your hobbies, and what you've been learning."
    self.section_slugs = %w[ career ]
    self.quick_replies = [
      "What could I move into from here?",
      "What's the cheapest way to test that?",
      "How would I retrain for it?",
      "What should I be asking that I'm not?"
    ]

    CONTEXT_SLUGS = %w[ career hobbies education ].freeze

    input :itch, required: true,
      label: "What's pushing you?",
      hint: "“I'm done with retail”, “my body can't do this job at 50”, “I want to work with my hands”."
    input :constraints,
      label: "Your constraints",
      hint: "Optional — “can't afford school”, “nights only”, “can't relocate”."

    BEHAVIOR = <<~PROMPT.freeze
      You are the career-exploration feature of a private, self-hosted life
      assistant — the guidance counselor most people never got. Rules of the
      room:
      - Ask before telling: what they like about the current work, what they
        hate, what a good week looks like, what constraints are real. One or
        two questions per turn, then listen.
      - Explore from their actual record: the jobs they've held, the wins
        they've logged, the hobbies they sink hours into, what they've been
        learning. A hobby done seriously is evidence of skill and appetite.
      - Surface adjacent moves their history supports — and always include
        the paths that don't run through a degree: trades, certificates,
        licenses, apprenticeships, self-employment. Name honest evergreen
        tradeoffs (schedule, body, licensing hurdles, seasonality).
      - Be placeholder-honest about anything current: never assert today's
        wages, local demand, or program costs — name exactly what to look up
        and where (occupational wage tables, state licensing boards, local
        program catalogs).
      - Push toward cheap tests over big leaps: one conversation with someone
        doing the job, one day shadowing, one small paid gig — before any
        tuition.
      - Short conversational turns, plain text, no lectures.
    PROMPT

    private
      def system_prompt
        parts = [ BEHAVIOR ]
        parts << "What's pushing the user: #{inputs[:itch]}"
        parts << "Their stated constraints: #{inputs[:constraints]}" if inputs[:constraints].present?
        context = section_context(CONTEXT_SLUGS)
        unless context.empty?
          parts << "The user's tracked record across Career, Hobbies, and Education — explore from this:\n#{context.to_prompt}"
        end
        parts << web_capability_note
        parts.compact.join("\n\n")
      end

      def opening_instruction
        "Open the conversation: reflect back in one sentence what seems to be pushing them (from their words and their record), then ask the one question that most narrows what the next move could be. Two or three sentences total."
      end

      def recap_instruction
        <<~TEXT
          The conversation is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: the directions explored and why each fit or didn't, the
          cheap next tests agreed on, and what to look up before going
          further — written so the user can pick the thread back up in a
          month. If retraining came up, note that the Learn-something tool
          can turn it into a plan. The title like "Next move — <direction>".
        TEXT
      end

      def recap_fallback_title = "Next move — where things stand"
  end
end
