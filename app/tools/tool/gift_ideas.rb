module Tool
  # The birthday radar's natural next step, and useful on its own: ideas
  # sized to what the user actually knows about the person — their notes,
  # their filing (a hobby tag is half the answer) — never invented facts.
  class GiftIdeas < Base
    self.title = "Gift ideas"
    self.description = "A short list of ideas that actually fit them, from what you know."
    self.section_slugs = %w[ people ]
    self.kind = :draft

    input :person_id, kind: :person, required: true,
      label: "Who's it for?"
    input :occasion,
      label: "What's the occasion?",
      hint: "Optional — “birthday March 12”, “housewarming”, “just because”."
    input :budget,
      label: "Budget?",
      hint: "Optional — “under $30”, “something small”."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the gift-ideas feature of a private, self-hosted life assistant.
      The draft is a numbered list of 5–8 gift ideas for this person, each one
      line: the idea, then a dash and why it fits *this* person specifically,
      grounded in what's known about them. Rules:
      - Never invent facts about the person; where knowledge runs out, make the
        idea a [BRACKETED PLACEHOLDER] naming what to find out ("[ask her
        sister] which authors she's into lately").
      - Respect the budget when one is given; lean cheap-and-thoughtful over
        expensive-and-generic. No gift cards unless the known facts argue for
        one.
      - Experiences and homemade things count.
      follow_ups: at most one — get the gift, dated ahead of the occasion when
      a real date is stated.
      #{DRAFT_FORMAT}
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The gift is for:\n#{person_context(person)}"
        parts << "Occasion: #{inputs[:occasion]}" if inputs[:occasion].present?
        parts << "Budget: #{inputs[:budget]}" if inputs[:budget].present?
        parts.join("\n\n")
      end

      def person = chosen_person

      def fallback_title = "Gift ideas for #{person.name}"

      # Filed under People plus the person's own filing — a hobby-buddy's
      # ideas land in the hobby lens too.
      def filing_sources = [ person ]
  end
end
