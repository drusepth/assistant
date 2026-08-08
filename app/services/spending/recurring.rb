# Subscription and bill detection, deterministically (docs/MONEY.md §4):
# a merchant charging a steady amount on a steady cadence. Pure
# arithmetic over the ledger — no model in the signal path (D20) — and
# shared by the new-recurring-charge and price-hike watchers so the two
# can never disagree about what counts as recurring.
class Spending::Recurring
  WINDOW_DAYS = 400
  MIN_CHARGES = 3
  # Monthly-ish: real billing dates drift with weekends and month lengths.
  MIN_GAP_DAYS = 24
  MAX_GAP_DAYS = 38
  # Amounts within this of each other are "the same charge" — covers tax
  # and usage jitter without swallowing a real price increase.
  AMOUNT_TOLERANCE = 0.05
  # A hike has to clear both bars to be worth speaking about.
  HIKE_FRACTION = 0.08
  HIKE_MIN_CENTS = 100

  Series = Struct.new(:merchant, :charges, keyword_init: true) do
    # Charges oldest → newest, each [ date, cents ] with cents positive.
    def latest = charges.last
    def latest_cents = latest.last
    def latest_on = latest.first
    def times = charges.size

    def previous_cents
      earlier = charges[0..-2].map(&:last)
      # The established price is what it charged most often before now —
      # one odd month can't masquerade as the old price.
      earlier.tally.max_by { |cents, count| [ count, -(cents - latest_cents).abs ] }&.first
    end

    def hike_cents
      return nil unless previous_cents

      jump = latest_cents - previous_cents
      return nil unless jump >= HIKE_MIN_CENTS && jump.to_f / previous_cents >= HIKE_FRACTION

      jump
    end
  end

  def initialize(user:)
    @user = user
  end

  # Every merchant that looks like a recurring charge, biggest first.
  def series
    @series ||= rows.group_by(&:merchant).filter_map do |merchant, group|
      charges = group.sort_by(&:occurred_on).map { |row| [ row.occurred_on, row.amount_cents.abs ] }
      next unless charges.size >= MIN_CHARGES
      next unless monthly_cadence?(charges.map(&:first))
      next unless steady_amounts?(charges.map(&:last))

      Series.new(merchant: merchant, charges: charges)
    end.sort_by { |series| -series.latest_cents }
  end

  private
    def rows
      SpendingTransaction.where(user_id: @user.id, transfer: false)
        .where(occurred_on: (Date.current - WINDOW_DAYS)..)
        .where.not(merchant: [ nil, "" ])
        .where(amount_cents: ...0)
        .to_a
    end

    def monthly_cadence?(dates)
      gaps = dates.each_cons(2).map { |earlier, later| (later - earlier).to_i }
      gaps.any? && gaps.all? { |gap| gap.between?(MIN_GAP_DAYS, MAX_GAP_DAYS) }
    end

    # Steady enough to be one subscription — a price *step* still counts as
    # steady (that's the hike the other watcher speaks about); wild variance
    # does not.
    def steady_amounts?(amounts)
      steps = amounts.uniq
      return true if steps.size == 1

      # At most one step, and each level internally tight.
      levels = amounts.chunk_while { |a, b| within_tolerance?(a, b) }.map { |chunk| chunk.sum / chunk.size }
      levels.size <= 2
    end

    def within_tolerance?(first, second)
      larger = [ first, second ].max
      return true if larger.zero?

      (first - second).abs.to_f / larger <= AMOUNT_TOLERANCE
    end
end
