module Watcher
  # The month-close ritual (docs/MONEY.md §4): once a month has rolled
  # over and there's something to look at, offer the review. One
  # suggestion per month ever — this is the quietest watcher in the app by
  # design, because a monthly ritual that pings twice isn't a ritual.
  # Accepting runs the spending review prefilled to that month.
  class MonthClose < Base
    self.section_slugs = %w[ budget money ]

    def scan
      month = Date.current.prev_month.beginning_of_month
      summary = Money::MonthSummary.new(user: user, month: month)
      return unless summary.any_activity?

      propose(
        fingerprint: "month:#{month.strftime("%Y-%m")}",
        kind: :insight,
        title: "Your #{month.strftime("%B")} review is ready",
        body: "#{month.strftime("%B")} is closed out — #{amount(summary.spent_cents)} spent. " \
              "Worth ten minutes to see where it went and what's worth changing.",
        action: {
          "tool" => { "slug" => "spending_review", "inputs" => { "month" => month.strftime("%Y-%m") } },
          "accept_label" => "See the review"
        }
      )
    end

    private
      def amount(cents) = "#{(cents / 100.0).round} #{user.household.currency}"
  end
end
