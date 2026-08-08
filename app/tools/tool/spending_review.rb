module Tool
  # "Where's my money going?" (D-money-coach, docs/MONEY.md §5.2) — the
  # facts half of the coach, and the month-close ritual. Code computes
  # every aggregate; the model narrates and prioritizes, and every number
  # it can print arrived in its input. The payoff is composition: the
  # audit ends in D28 next-step cards that open the cancellation letter or
  # the bill negotiation with the merchant already filled in.
  class SpendingReview < Base
    self.title = "Where's my money going?"
    self.description = "A plain-language read of your month, and the specific cuts worth making."
    self.section_slugs = %w[ money budget subscriptions ]
    self.kind = :draft

    MAX_CUTS = 5
    ROUTABLE = %w[ cancel_subscription negotiation_prep money_coach ].freeze

    input :month, kind: :ledger_month, label: "Which month?"
    input :focus, label: "Anything you want me to look at?",
      hint: "Optional — “why was December so bad”, “find me $200 a month”."

    Cut = Data.define(:what, :monthly_cents, :how)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the spending-review feature of a private, self-hosted life
      assistant. You are handed numbers that were computed from the user's own
      imported bank data — you never see raw transactions, and you never
      calculate new totals. Your job is to explain the month in plain language
      and name the specific cuts worth considering.

      Respond with a JSON object:
      {"review": {"title": "...", "body": "..."},
       "cuts": [{"what": "...", "monthly_amount": 12.99, "how": "...",
                 "tool": "cancel_subscription" | "negotiation_prep" | null}, ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}

      The review body: three or four short paragraphs. What went to plan; what
      didn't and what *might* explain it — asked as a question, never asserted
      as fact about their life; the recurring charges worth a second look; and
      one honest sentence about the month overall. No preamble, no summary of
      what a budget is.

      cuts: at most #{MAX_CUTS}, biggest realistic saving first. Every one must trace to a
      number you were given — `monthly_amount` is that number, not an estimate.
      `what` names the thing ("Netflix", "the phone plan"). `how` is the concrete
      move in one sentence. `tool` routes the user to the right next step:
      "cancel_subscription" for a subscription they'd drop, "negotiation_prep"
      for a bill worth negotiating down, null when it's just a habit change.

      Hard rules:
      - Never invent an amount, a merchant, or a trend. If the data is thin, say
        the data is thin.
      - Never moralize. "Dining out is 340 a month, more than groceries" is an
        observation; "you're eating out too much" is a verdict, and not yours to
        make. Describe, propose, let them decide.
      - Cutting something they clearly value is a last resort — say so plainly if
        the only real savings left are things that matter to them.
      - No investment, tax, or credit-product advice of any kind.
    PROMPT

    class << self
      # The month picker is built per user at form time: the months their
      # ledger actually spans, newest first (an empty ledger offers the
      # current month, and the review says the data is thin).
      def month_options(user)
        months = SpendingTransaction.where(user_id: user.id)
          .distinct.order(occurred_on: :desc).limit(400).pluck(:occurred_on)
          .map(&:beginning_of_month).uniq.first(24)
        months = [ Date.current.prev_month.beginning_of_month ] if months.empty?
        months.map { |month| [ month.strftime("%B %Y"), month.strftime("%Y-%m") ] }
      end
    end

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [
          "Today's date: #{Date.current.iso8601}",
          "Currency: #{user.household.currency}",
          "The month under review: #{month.strftime("%B %Y")}"
        ]
        parts << month_block
        parts << aggregates.to_prompt if aggregates.any?
        parts << "What the user asked you to look at: #{inputs[:focus]}" if inputs[:focus].present?
        parts.compact.join("\n\n")
      end

      # The month's own numbers, code-computed: envelopes against targets,
      # what landed outside them, and what came in.
      def month_block
        rows = summary.lines.select { |line| line.target? || line.spent_cents.positive? }.map do |line|
          target = line.target? ? " (target #{amount(line.target_cents)})" : " (no target)"
          "- #{line.category.name}: #{amount(line.spent_cents)}#{target}"
        end

        parts = [ "#{month.strftime("%B")} by envelope:" ]
        parts << (rows.any? ? rows.join("\n") : "- nothing categorized this month")
        parts << "Spending outside any envelope: #{amount(summary.unbudgeted_cents)}" if summary.unbudgeted_cents.positive?
        parts << "Total spent: #{amount(summary.spent_cents)}"
        parts << "Money in: #{amount(summary.income_cents)}" if summary.income_cents.positive?
        parts.join("\n")
      end

      def handle(response)
        body = response.dig("review", "body")
        raise Llm::Error, "The model didn't return a review — try again." if body.blank?

        cuts = parsed_cuts(response["cuts"])

        create_note(
          title: response.dig("review", "title").presence || fallback_title,
          body: [
            body,
            cut_block(cuts),
            provenance_footer
          ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
        store_next_tools(next_tool_proposals(response["cuts"]), allowed: ROUTABLE)
      end

      # Cuts are validated the same way envelopes are: a number we can
      # print, or the entry is dropped.
      def parsed_cuts(list)
        Array(list).filter_map do |entry|
          next unless entry.is_a?(Hash) && entry["what"].present?

          cents = cut_cents(entry["monthly_amount"])
          next unless cents

          Cut.new(what: entry["what"].to_s.squish.first(80), monthly_cents: cents,
            how: entry["how"].to_s.strip.presence)
        end.first(MAX_CUTS)
      end

      def cut_cents(value)
        return nil unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+(\.\d+)?\z/)

        cents = (value.to_f * 100).round
        cents if cents.positive?
      end

      # The composition payoff (D28): the audit's cuts become prefilled
      # next-step cards — the cancellation letter with the subscription
      # named, the negotiation prep with the bill named. The model proposes
      # a slug and a name; code builds the payload and validates it.
      def next_tool_proposals(list)
        Array(list).filter_map do |entry|
          next unless entry.is_a?(Hash) && entry["what"].present?

          case entry["tool"].to_s
          when "cancel_subscription"
            { "slug" => "cancel_subscription",
              "inputs" => { "service" => entry["what"].to_s.squish.first(80) },
              "reason" => "Draft the cancellation for #{entry["what"]}." }
          when "negotiation_prep"
            { "slug" => "negotiation_prep",
              "inputs" => { "scenario" => "lowering the #{entry["what"].to_s.squish.first(60)} bill" },
              "reason" => "Prep the call to bring #{entry["what"]} down." }
          end
        end
      end

      def cut_block(cuts)
        return nil if cuts.none?

        lines = cuts.map do |cut|
          "- #{cut.what}: about #{amount(cut.monthly_cents)}/month#{" — #{cut.how}" if cut.how}"
        end
        "Worth a look:\n#{lines.join("\n")}"
      end

      # Appended by code: what was actually read, so the review can never
      # overstate its own basis.
      def provenance_footer
        counted = SpendingTransaction.where(user_id: user.id).in_month(month).where(transfer: false).count
        "Based on #{counted} #{"transaction".pluralize(counted)} in your ledger for " \
        "#{month.strftime("%B %Y")}#{" — anything you haven't imported isn't in here" if counted.positive?}."
      end

      def month
        @month ||= begin
          Date.strptime(inputs[:month].to_s, "%Y-%m")
        rescue Date::Error
          Date.current.prev_month.beginning_of_month
        end
      end

      def summary = @summary ||= Money::MonthSummary.new(user: user, month: month)

      def aggregates = @aggregates ||= Spending::Aggregates.new(user: user)

      def amount(cents) = "#{(cents / 100.0).round} #{user.household.currency}"

      def fallback_title = "#{month.strftime("%B %Y")} — where the money went"
  end
end
