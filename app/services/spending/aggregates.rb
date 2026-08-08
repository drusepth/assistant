# Code-computed aggregates over the ledger — the numbers the budget tools
# reason from (MONEY.md §3.2/§5.2): the model never sees raw transaction
# rows; code aggregates, the model narrates. Also the injection seam:
# merchant strings pass through, but every amount in a tool's output
# should trace back to a number computed here.
class Spending::Aggregates
  WINDOW_DAYS = 90
  TOP_MERCHANTS = 12
  RECURRING_TOLERANCE_CENTS = 200

  def initialize(user:, window_days: WINDOW_DAYS)
    @user = user
    @since = Date.current - window_days
    @window_days = window_days
  end

  def any? = rows.any?

  def months_covered
    return 0 if rows.empty?
    span_days = (rows.map(&:occurred_on).max - rows.map(&:occurred_on).min).to_i + 1
    [ (span_days / 30.44).round, 1 ].max
  end

  # name → monthly-average cents spent, for categorized spending.
  def monthly_by_category
    @monthly_by_category ||= begin
      categories = @user.budget_categories.index_by(&:id)
      totals = spending_rows.group_by(&:budget_category_id).transform_values { |group| group.sum { |row| row.amount_cents.abs } }
      totals.each_with_object({}) do |(category_id, cents), monthly|
        name = categories[category_id]&.name || "(uncategorized)"
        monthly[name] = (monthly[name] || 0) + cents / months_covered
      end.sort_by { |_name, cents| -cents }.to_h
    end
  end

  # merchant → total cents in the window, biggest first.
  def top_merchants
    @top_merchants ||= spending_rows.reject { |row| row.merchant.blank? }
      .group_by(&:merchant).transform_values { |group| group.sum { |row| row.amount_cents.abs } }
      .sort_by { |_merchant, cents| -cents }.first(TOP_MERCHANTS).to_h
  end

  # Merchants charging a steady amount at a steady cadence — subscription-
  # and bill-shaped. [ { merchant:, cents:, times: } ], biggest first.
  def recurring
    @recurring ||= spending_rows.reject { |row| row.merchant.blank? }
      .group_by(&:merchant)
      .filter_map do |merchant, group|
        next if group.size < 2
        amounts = group.map { |row| row.amount_cents.abs }
        next unless amounts.max - amounts.min <= RECURRING_TOLERANCE_CENTS

        { merchant: merchant, cents: amounts.max, times: group.size }
      end
      .sort_by { |entry| -entry[:cents] }
  end

  def income_monthly_cents
    @income_monthly_cents ||= rows.select(&:money_in?).sum(&:amount_cents) / months_covered
  end

  # The compact text block tools inject — code-built, clearly labeled as
  # computed numbers with their provenance (the Tier-A honesty line).
  def to_prompt
    return nil unless any?

    parts = [ "Computed from the user's imported spending, last #{months_covered} #{"month".pluralize(months_covered)}:" ]
    if monthly_by_category.any?
      parts << "Monthly average spending by category:\n" +
        monthly_by_category.first(15).map { |name, cents| "- #{name}: #{amount(cents)}" }.join("\n")
    end
    if recurring.any?
      parts << "Recurring charges (steady amount, repeated):\n" +
        recurring.first(10).map { |entry| "- #{entry[:merchant]}: #{amount(entry[:cents])} × #{entry[:times]}" }.join("\n")
    end
    if top_merchants.any?
      parts << "Top merchants by total spend:\n" +
        top_merchants.map { |merchant, cents| "- #{merchant}: #{amount(cents)}" }.join("\n")
    end
    parts << "Observed monthly income (deposits): #{amount(income_monthly_cents)}" if income_monthly_cents.positive?
    parts.join("\n\n")
  end

  private
    def rows
      @rows ||= SpendingTransaction.where(user_id: @user.id, transfer: false)
        .where(occurred_on: @since..).to_a
    end

    def spending_rows = rows.select(&:money_out?)

    def amount(cents) = "#{(cents / 100.0).round} #{@user.household.currency}"
end
