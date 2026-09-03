module Tool
  # The relationship analog of the Rights letter family: social scripts for
  # people who weren't handed them. A chat, not a one-shot draft, because
  # hard conversations have a second turn — "here's what they said back."
  # The only primitive it produces is an explicit recap (D29).
  class WhatDoISay < ChatBase
    self.title = "What do I say?"
    self.description = "A coach for the hard conversations — check-ins, apologies, boundaries, asks, condolences."
    self.section_slugs = %w[ people ]
    self.quick_replies = [
      "Here's what they said back — now what?",
      "Make it warmer",
      "Make it shorter",
      "I'm not sure I can say that"
    ]

    SITUATIONS = [
      "Check in on someone who's struggling",
      "Apologize",
      "Condolences",
      "Ask for help",
      "Set a boundary",
      "Invite someone to something",
      "Say no to something",
      "Something else"
    ].freeze

    input :situation, kind: :select, required: true, options: SITUATIONS,
      label: "What kind of conversation?"
    input :person_id, kind: :person,
      label: "Who's it with?"
    input :details,
      label: "What's going on?",
      hint: "Optional — the more context, the better the words."

    BEHAVIOR = <<~PROMPT.freeze
      You are the what-do-I-say feature of a private, self-hosted life
      assistant: a coach for hard conversations. Rules of the room:
      - Work toward words the user would actually say — plain, honest, in
        their register, never greeting-card language.
      - Offer a short draft early, then refine it together; when one key fact
        is missing, ask that one question first.
      - Short turns, this is a dialogue. Plain conversational text only.
      - Honesty over technique: no manipulation, no scripts to pressure or
        corner the other person, no pretending to know how they feel.
      - Boundaries and "no" get to be kind *and* unambiguous — don't soften a
        message into not being said.
      - For grief and check-ins: presence beats eloquence; offer the concrete
        ("I'm bringing dinner Tuesday") over the open-ended ("let me know if
        you need anything").
      - The user decides what they're willing to say; when they push back on a
        draft, follow them, not the technique.
      - Where a person's record is given, it says which pronoun the user uses
        for them. Use it, and never guess one from a name.
    PROMPT

    private
      def system_prompt
        parts = [ BEHAVIOR ]
        parts << "The conversation: #{inputs[:situation]}"
        parts << "It's with:\n#{person_context(person)}" if person
        parts << "What's going on: #{inputs[:details]}" if inputs[:details].present?
        parts.join("\n\n")
      end

      def opening_instruction
        "Open the session: reflect the situation back in one sentence, then either offer a short first draft of what to say or — if one key fact is missing — ask the single most useful question. Never both."
      end

      def recap_instruction
        <<~TEXT
          The session is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: the message or talking points as last agreed, plus any
          when/how notes — written so the user can send or say it straight from
          the note. The title like "What to say — <situation>".
        TEXT
      end

      def person = chosen_person

      def recap_fallback_title = "What to say — #{inputs[:situation].to_s.downcase}"

      # Recaps file under People plus the person's own filing, when the
      # conversation names one.
      def filing_sources = [ person ].compact
  end
end
