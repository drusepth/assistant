require "test_helper"

# The Money and Budget lead panels (D37 convention, docs/MONEY.md §3.3).
class MoneyPanelsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
  end

  test "the Money page invites before there's a ledger, and reports after" do
    get section_path("money")
    assert_response :success
    assert_match "Where does the money go?", response.body

    spend(45_00)
    get section_path("money")
    assert_match "so far", response.body
    assert_no_match(/Where does the money go\?/, response.body)
  end

  test "the Budget page leads with the build tool until envelopes exist" do
    get section_path("budget")
    assert_response :success
    assert_match "A budget you own, in two minutes", response.body
    assert_match new_tool_run_path("build_my_budget"), response.body

    @user.budget_categories.create!(name: "Groceries", group: "needs", monthly_target_cents: 50_000)
    spend(20_000)
    get section_path("budget")

    assert_match "Groceries", response.body
    assert_no_match(/A budget you own/, response.body)
  end

  test "panels never show another member's spending" do
    their_account = users(:two).spending_accounts.create!(name: "Theirs", kind: "checking")
    SpendingTransaction.create!(user_id: users(:two).id, spending_account_id: their_account.id,
      occurred_on: Date.current, amount_cents: -99_999, descriptor: "THEIR SECRET",
      fingerprint: "t-#{SecureRandom.hex(4)}", source: "statement")

    get section_path("money")

    assert_no_match(/999/, response.body)
    assert_match "Where does the money go?", response.body
  end

  test "the panel hides the Act-zone card it carries itself" do
    assert_includes Sections::Panels::Money.new(section: sections(:money), viewer: @user).hidden_tool_slugs,
      "build_my_budget"
  end

  private
    def spend(cents, category: nil)
      SpendingTransaction.create!(
        user_id: @user.id, spending_account_id: @account.id,
        occurred_on: Date.current, amount_cents: -cents, descriptor: "SAFEWAY",
        budget_category_id: category&.id,
        fingerprint: "t-#{SecureRandom.hex(6)}", source: "statement")
    end
end
