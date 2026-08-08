require "test_helper"

class Spending::CategorizeTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
    @groceries = @user.budget_categories.create!(name: "Groceries", group: "needs")
    @fun = @user.budget_categories.create!(name: "Fun money", group: "wants")
  end

  test "a taught rule beats the keyword table" do
    @user.spending_rules.create!(matcher: "safeway", budget_category: @fun)
    row = make_row("SAFEWAY STORE")

    Spending::Categorize.new(user: @user).apply_deterministic

    assert_equal @fun.id, row.reload.budget_category_id
    assert_equal "rule", row.categorized_by
  end

  test "the longest matching rule wins" do
    @user.spending_rules.create!(matcher: "amazon", budget_category: @fun)
    @user.spending_rules.create!(matcher: "amazon fresh", budget_category: @groceries)
    row = make_row("AMAZON FRESH ORDER")

    Spending::Categorize.new(user: @user).apply_deterministic

    assert_equal @groceries.id, row.reload.budget_category_id
  end

  test "keywords file into a matching category name, and skip when the user has none" do
    grocery_row = make_row("TRADER JOE'S #552")
    fuel_row = make_row("CHEVRON STATION") # user has no Transport category

    Spending::Categorize.new(user: @user).apply_deterministic

    assert_equal @groceries.id, grocery_row.reload.budget_category_id
    assert_equal "keyword", grocery_row.categorized_by
    assert_nil fuel_row.reload.budget_category_id
  end

  test "a new rule applies backwards over automatic verdicts but never a hand-set one" do
    auto_row = make_row("NETFLIX.COM")
    auto_row.update!(budget_category_id: @groceries.id, categorized_by: "model")
    hand_row = make_row("NETFLIX.COM")
    hand_row.update!(budget_category_id: @groceries.id, categorized_by: "user")

    rule = @user.spending_rules.create!(matcher: "netflix", budget_category: @fun)
    Spending::Categorize.new(user: @user).apply_rule(rule)

    assert_equal @fun.id, auto_row.reload.budget_category_id
    assert_equal @groceries.id, hand_row.reload.budget_category_id
  end

  test "model labels apply only when they echo real merchants and real categories" do
    coffee = make_row("BLUE BOTTLE COFFEE")
    mystery = make_row("XR-2000 HOLDINGS")

    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: {
        assignments: [
          { merchant: "BLUE BOTTLE COFFEE", category: "fun MONEY" },     # case-insensitive match
          { merchant: "XR-2000 HOLDINGS", category: "Crypto" },          # unknown category → dropped
          { merchant: "SOMETHING WE NEVER SENT", category: "Groceries" } # unknown merchant → dropped
        ]
      }.to_json } } ]
    }.to_json)

    Spending::Categorize.new(user: @user).classify_with_model(model_profiles(:smith))

    assert_equal @fun.id, coffee.reload.budget_category_id
    assert_equal "model", coffee.categorized_by
    assert_nil mystery.reload.budget_category_id
  end

  test "transfers are never categorized" do
    row = make_row("SAFEWAY STORE")
    row.update!(transfer: true)
    @user.spending_rules.create!(matcher: "safeway", budget_category: @groceries)

    Spending::Categorize.new(user: @user).apply_deterministic

    assert_nil row.reload.budget_category_id
  end

  private
    def make_row(descriptor, cents: -1000)
      SpendingTransaction.create!(
        user_id: @user.id, spending_account_id: @account.id,
        occurred_on: Date.current, amount_cents: cents, descriptor: descriptor,
        merchant: Spending::Normalize.merchant(descriptor),
        fingerprint: "test-#{SecureRandom.hex(6)}", source: "statement")
    end
end
