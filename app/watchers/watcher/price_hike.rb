module Watcher
  # "Your internet went from 65 to 82." (docs/MONEY.md §4) — the Bills
  # subsection's long-promised price-hike detection, and it needs nothing
  # but the ledger and arithmetic. Providers count on the increase going
  # unnoticed; this is the whole feature. One suggestion per merchant per
  # price step, and accepting opens the negotiation prep with the bill
  # named.
  class PriceHike < Base
    self.section_slugs = %w[ bills money subscriptions ]

    def scan
      Spending::Recurring.new(user: user).series.each do |series|
        jump = series.hike_cents or next

        propose(
          fingerprint: "merchant:#{series.merchant.downcase}/#{series.latest_cents}",
          kind: :heads_up,
          title: "#{series.merchant} went from #{amount(series.previous_cents)} to #{amount(series.latest_cents)}",
          body: "That's #{amount(jump)} more a month — about #{amount(jump * 12)} a year. " \
                "Increases like this usually come off with one phone call, and cancelling is the other option.",
          action: {
            "tool" => { "slug" => "negotiation_prep",
                        "inputs" => { "scenario" => "lowering the #{series.merchant} bill",
                                      "constraints" => "It went from #{amount(series.previous_cents)} to " \
                                                       "#{amount(series.latest_cents)} a month." } },
            "accept_label" => "Prep the call"
          }
        )
      end
    end

    private
      def amount(cents) = "#{format("%.2f", cents / 100.0)} #{user.household.currency}"
  end
end
