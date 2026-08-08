require "test_helper"

class Money::MonthSummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
    @groceries = @user.budget_categories.create!(name: "Groceries", group: "needs", monthly_target_cents: 50_000)
    @fun = @user.budget_categories.create!(name: "Fun money", group: "wants", monthly_target_cents: 10_000)
  end

  test "spend and targets roll up per category and per group" do
    spend(@groceries, 12_000)
    spend(@groceries, 8_000)
    spend(@fun, 2_500)

    summary = Money::MonthSummary.new(user: @user)
    groceries = summary.lines.find { |line| line.category == @groceries }

    assert_equal 20_000, groceries.spent_cents
    assert_equal 30_000, groceries.remaining_cents
    assert_not groceries.over?
    assert_equal 20_000, summary.group_spent_cents("needs")
    assert_equal 50_000, summary.group_target_cents("needs")
    assert_equal 22_500, summary.spent_cents
  end

  test "a refund nets against its envelope instead of counting as income" do
    spend(@groceries, 10_000)
    row(@groceries, 3_000) # returned the roast

    summary = Money::MonthSummary.new(user: @user)

    assert_equal 7_000, summary.lines.find { |line| line.category == @groceries }.spent_cents
    assert_equal 0, summary.income_cents
  end

  test "an over-refunded envelope floors at zero rather than going negative" do
    spend(@groceries, 1_000)
    row(@groceries, 5_000)

    assert_equal 0, Money::MonthSummary.new(user: @user).lines.find { |line| line.category == @groceries }.spent_cents
  end

  test "uncategorized spending is visible as unbudgeted, never hidden" do
    spend(nil, 4_000)

    summary = Money::MonthSummary.new(user: @user)

    assert_equal 4_000, summary.unbudgeted_cents
    assert_equal 4_000, summary.spent_cents
  end

  test "transfers never count as spending or income" do
    transfer = row(nil, -25_000)
    transfer.update!(transfer: true)
    incoming = row(nil, 25_000)
    incoming.update!(transfer: true)

    summary = Money::MonthSummary.new(user: @user)

    assert_equal 0, summary.spent_cents
    assert_equal 0, summary.income_cents
  end

  test "income lands from uncategorized deposits and income-group categories" do
    payroll = @user.budget_categories.create!(name: "Paycheck", group: "income")
    row(payroll, 200_000)
    row(nil, 5_000)

    summary = Money::MonthSummary.new(user: @user)

    assert_equal 205_000, summary.income_cents
    assert_not_includes summary.expense_categories, payroll
  end

  test "other months and other users stay out of the month" do
    spend(@groceries, 9_000, on: Date.current.prev_month.beginning_of_month)
    their_account = users(:two).spending_accounts.create!(name: "Theirs", kind: "checking")
    SpendingTransaction.create!(user_id: users(:two).id, spending_account_id: their_account.id,
      occurred_on: Date.current, amount_cents: -7_000, descriptor: "THEIRS",
      fingerprint: "x-#{SecureRandom.hex(4)}", source: "statement")

    assert_equal 0, Money::MonthSummary.new(user: @user).spent_cents
    assert_equal 9_000, Money::MonthSummary.new(user: @user, month: Date.current.prev_month).spent_cents
  end

  test "pace flags a category running ahead of the month, and past months read as whole" do
    travel_to Date.new(2026, 6, 5) do # 5/30 through June
      spend(@fun, 9_000) # 90% of a 100.00 envelope

      summary = Money::MonthSummary.new(user: @user)
      fun_line = summary.lines.find { |line| line.category == @fun }

      assert summary.over_pace?(fun_line)
      assert_not summary.over_pace?(summary.lines.find { |line| line.category == @groceries })
      assert_equal 25, summary.days_left
    end

    assert_equal 1.0, Money::MonthSummary.new(user: @user, month: 3.months.ago).month_fraction
  end

  test "budgeted? and any_activity? drive the panel's empty states" do
    bare = users(:two)
    assert_not Money::MonthSummary.new(user: bare).budgeted?
    assert_not Money::MonthSummary.new(user: bare).any_activity?

    assert Money::MonthSummary.new(user: @user).budgeted?
  end

  private
    def spend(category, cents, on: Date.current) = row(category, -cents, on: on)

    def row(category, cents, on: Date.current)
      SpendingTransaction.create!(
        user_id: @user.id, spending_account_id: @account.id,
        occurred_on: on, amount_cents: cents, descriptor: "ROW",
        budget_category_id: category&.id,
        fingerprint: "test-#{SecureRandom.hex(6)}", source: "statement")
    end
end
