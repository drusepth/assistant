require "test_helper"

class Spending::QuickLogTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "logs money out today on an auto-created cash account" do
    row = Spending::QuickLog.call(user: @user, text: "14.50 lunch at the taqueria")

    assert_equal(-1450, row.amount_cents)
    assert_equal Date.current, row.occurred_on
    assert_equal "manual", row.source
    assert_equal "cash", row.spending_account.kind
    assert_equal "lunch at the taqueria", row.descriptor
  end

  test "a plus sign logs money in, and the cash account is reused" do
    first = Spending::QuickLog.call(user: @user, text: "12 coffee")
    second = Spending::QuickLog.call(user: @user, text: "+500 side gig payout")

    assert_equal 50_000, second.amount_cents
    assert_equal first.spending_account_id, second.spending_account_id
    assert_equal 1, @user.spending_accounts.count
  end

  test "unparseable text returns nil and logs nothing" do
    assert_nil Spending::QuickLog.call(user: @user, text: "lunch 14.50")
    assert_nil Spending::QuickLog.call(user: @user, text: "")
    assert_equal 0, SpendingTransaction.where(user_id: @user.id).count
  end

  test "logged rows run through deterministic categorization" do
    category = @user.budget_categories.create!(name: "Dining out", group: "wants")
    @user.spending_rules.create!(matcher: "taqueria", budget_category: category)

    row = Spending::QuickLog.call(user: @user, text: "14.50 taqueria")

    assert_equal category.id, row.reload.budget_category_id
  end
end
