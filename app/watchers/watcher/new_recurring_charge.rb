module Watcher
  # "Looks like a new subscription: Calm, about 12.99 a month." (docs/MONEY.md §4)
  # A merchant that has quietly become a monthly habit is worth *knowing*
  # about — free trials that converted, the service you forgot you signed
  # up for. Deterministic (Spending::Recurring), one suggestion per
  # merchant ever, and accepting files it under Subscriptions with its
  # renewal on the calendar, which is what makes renewal-radar work on it
  # from then on.
  class NewRecurringCharge < Base
    self.section_slugs = %w[ subscriptions money ]

    # Only speak about series that started recently — an old, known
    # subscription isn't news, it's just your life.
    RECENT_START = 120.days

    def scan
      Spending::Recurring.new(user: user).series.each do |series|
        next unless series.charges.first.first >= RECENT_START.ago.to_date
        next if series.hike_cents # that's price_hike's story, not this one

        monthly = amount(series.latest_cents)
        next_due = series.latest_on + 30

        propose(
          fingerprint: "merchant:#{series.merchant.downcase}",
          kind: :insight,
          title: "Looks like a new subscription: #{series.merchant}, about #{monthly} a month",
          body: "Charged #{series.times} times since #{series.charges.first.first.strftime("%B")}. " \
                "If you want it, filing it puts the renewal on your calendar; if you don't, " \
                "the cancellation letter is one click.",
          action: {
            "task" => { "title" => "Decide about #{series.merchant} (#{monthly}/month)",
                        "notes" => "Spotted in your spending — cancel it, or file it as a subscription you meant to have." },
            "event" => { "title" => "#{series.merchant} renews (about #{monthly})",
                         "starts_at" => next_due.iso8601, "all_day" => true },
            "accept_label" => "File it"
          }
        )
      end
    end

    private
      def amount(cents) = "#{format("%.2f", cents / 100.0)} #{user.household.currency}"
  end
end
