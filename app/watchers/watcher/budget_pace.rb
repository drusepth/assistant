module Watcher
  # "Groceries is at 470 of 520 with 12 days left." (D-money-coach,
  # docs/MONEY.md §4) — a pace fact, never a verdict about how someone
  # spends. Deterministic arithmetic over the derived month summary, one
  # nudge per envelope per month *ever* (the fingerprint carries the
  # month), and no signal means no nudge: an envelope without a target, or
  # a user without a ledger, is silence rather than a hollow scold.
  # Accepting opens the coach with that envelope preloaded.
  class BudgetPace < Base
    self.section_slugs = %w[ budget money ]

    # Loud enough to matter: most of the envelope gone with real time left.
    SPENT_THRESHOLD = 0.85
    MIN_DAYS_LEFT = 7

    def scan
      summary = Money::MonthSummary.new(user: user)
      return unless summary.days_left >= MIN_DAYS_LEFT

      summary.lines.each do |line|
        next unless line.target?
        next unless line.fraction_spent >= SPENT_THRESHOLD
        next unless summary.over_pace?(line)

        propose(
          fingerprint: "category:#{line.category.id}/#{summary.month.strftime("%Y-%m")}",
          kind: :heads_up,
          title: pace_title(line, summary),
          body: "That's ahead of where the month is. Worth a look while there's still room to steer — " \
                "or leave it, if this month is just like that.",
          action: {
            "tool" => { "slug" => "money_coach",
                        "inputs" => { "category_id" => line.category.id.to_s,
                                      "about" => "planning the rest of the month for #{line.category.name}" } },
            "accept_label" => "Talk it through"
          }
        )
      end
    end

    private
      def pace_title(line, summary)
        spent = whole(line.spent_cents)
        target = whole(line.target_cents)
        if line.over?
          "#{line.category.name} is past its #{target} target, #{summary.days_left} days left"
        else
          "#{line.category.name} is at #{spent} of #{target}, #{summary.days_left} days left"
        end
      end

      def whole(cents) = "#{(cents / 100.0).round} #{user.household.currency}"
  end
end
