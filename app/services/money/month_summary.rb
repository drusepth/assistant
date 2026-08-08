# One month of budget-vs-actual, computed fresh from the ledger every
# time (D-budget-envelopes, MONEY.md §3.1) — the CareRadar idiom: a
# derived view holds no state, so it can never disagree with what it
# reads. All amounts are positive cents in "spent/earned" terms; the
# signed-ledger convention stays inside the queries.
class Money::MonthSummary
  Line = Struct.new(:category, :spent_cents, :target_cents, keyword_init: true) do
    def target? = target_cents.present? && target_cents.positive?
    def remaining_cents = target? ? target_cents - spent_cents : nil
    def over? = target? && spent_cents > target_cents
    def fraction_spent = target? ? spent_cents.to_f / target_cents : nil
  end

  # A category is meaningfully over-pace when its spend-fraction leads the
  # month-fraction by more than this margin — meters inform, not scold.
  PACE_MARGIN = 0.15

  attr_reader :month

  def initialize(user:, month: Date.current.beginning_of_month)
    @user = user
    @month = month.beginning_of_month
  end

  def categories = @categories ||= @user.budget_categories.active.ordered.to_a

  def expense_categories = categories.reject(&:income?)

  def lines
    @lines ||= expense_categories.map do |category|
      Line.new(category: category,
        spent_cents: spent_by_category.fetch(category.id, 0),
        target_cents: category.monthly_target_cents)
    end
  end

  def lines_for(group) = lines.select { |line| line.category.group == group }

  def group_spent_cents(group) = lines_for(group).sum(&:spent_cents)

  def group_target_cents(group)
    targets = lines_for(group).filter_map(&:target_cents)
    targets.any? ? targets.sum : nil
  end

  def spent_cents = @spent_cents ||= lines.sum(&:spent_cents) + unbudgeted_cents

  def target_cents
    targets = lines.filter_map(&:target_cents)
    targets.any? ? targets.sum : nil
  end

  # Spending that landed in no envelope — visible, never hidden, so the
  # meters can't quietly understate the month.
  def unbudgeted_cents
    @unbudgeted_cents ||= -month_scope.spending.uncategorized.sum(:amount_cents)
  end

  # Deposits that aren't a refund into an expense envelope: uncategorized
  # money in, plus anything filed under an income-group category.
  def income_cents
    @income_cents ||= month_scope.where(transfer: false)
      .where(budget_category_id: [ nil ] + categories.select(&:income?).map(&:id))
      .where(amount_cents: 1..).sum(:amount_cents)
  end

  def planned_income_cents
    targets = categories.select(&:income?).filter_map(&:monthly_target_cents)
    targets.any? ? targets.sum : nil
  end

  def kept_cents = income_cents - spent_cents

  # How far through the month we are: 0..1, whole months land on 1.
  def month_fraction
    return 1.0 if month < Date.current.beginning_of_month
    return 0.0 if month > Date.current

    Date.current.day.to_f / month.end_of_month.day
  end

  def days_left
    return 0 unless current?
    month.end_of_month.day - Date.current.day
  end

  def current? = month == Date.current.beginning_of_month

  def over_pace?(line)
    line.target? && line.fraction_spent > month_fraction + PACE_MARGIN
  end

  def any_activity? = spent_cents.positive? || income_cents.positive?

  def budgeted? = expense_categories.any? { |category| category.monthly_target_cents.present? }

  private
    # Net per category — a refund is a positive row in the same envelope
    # (Q-splits-and-refunds), so it offsets rather than counting as income.
    def spent_by_category
      @spent_by_category ||= month_scope.where(transfer: false)
        .where(budget_category_id: expense_categories.map(&:id))
        .group(:budget_category_id).sum(:amount_cents)
        .transform_values { |cents| [ -cents, 0 ].max }
    end

    def month_scope
      SpendingTransaction.where(user_id: @user.id).in_month(@month)
    end
end
