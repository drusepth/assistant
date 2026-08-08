module Tool
  # PRODUCT.md's "event planning" line, sized for real life: the taco night
  # that actually happens beats the dinner party that never does. The Event
  # lands by code — plan_goal! produces Goal + Tasks only — and lands first,
  # so a model failure still leaves the date on the calendar.
  class GetTogether < Base
    self.title = "Plan a get-together"
    self.description = "From “we should hang out” to a date on the calendar, with the steps to make it happen."
    self.section_slugs = %w[ people ]
    self.kind = :plan

    input :occasion, required: true,
      label: "What's the occasion?",
      hint: "“Taco night with the Nguyens”, “Mom's 60th”, “D&D one-shot”."
    input :who,
      label: "Who's coming?",
      hint: "Optional — names, or “the book club”."
    input :on, kind: :date,
      label: "When?",
      hint: "Optional — with a date the plan works backwards from it; without one, picking a date is step one."

    BRIEF = <<~BRIEF.freeze
      This goal is planning a small social gathering. Steer hard toward small,
      cheap, and actually-scheduled — the point is that it happens, not that
      it impresses:
      - Inviting people comes first (people flake less on a date they helped
        pick); one step is reaching out to the guests.
      - Food and logistics stay simple: potluck, one dish, takeout — no step
        should require special equipment or a full day of cooking.
      - Include a day-before step: confirm with guests and do the one prep
        thing that matters.
      - When a date is given, schedule the steps backward from it — invites
        earliest. When no date is given, the first step is proposing 2–3
        dates to the guests.
      File the steps under people; shopping steps may add money.
    BRIEF

    def call
      # Deterministic part first: the calendar date survives a model failure.
      create_event(title: inputs[:occasion].to_s.strip, on: date) if date
      plan_goal!(title: inputs[:occasion].to_s.strip, brief: brief_text, description: description_text)
    end

    private
      def date = parsed_date(inputs[:on])

      def brief_text
        date ? "#{BRIEF}\nThe gathering is on #{date.iso8601}; it is already on the calendar — don't add a step to schedule it." : BRIEF
      end

      def description_text
        [ inputs[:who].presence && "Who: #{inputs[:who]}",
          date && "When: #{date.strftime("%B %-d, %Y")}" ].compact.join("\n").presence
      end
  end
end
