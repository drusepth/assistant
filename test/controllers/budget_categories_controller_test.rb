require "test_helper"

class BudgetCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "a target typed here is hand-set, so the tool can never overwrite it" do
    post budget_categories_path, params: { name: "Groceries", group: "needs", monthly_target: "520.50" }

    category = @user.budget_categories.sole
    assert_equal 52_050, category.monthly_target_cents
    assert_equal "user", category.target_set_by
    assert category.target_hand_set?
  end

  test "editing a target marks it hand-set even when the tool set it first" do
    category = @user.budget_categories.create!(name: "Dining out", group: "wants",
      monthly_target_cents: 10_000, target_set_by: "tool")

    patch budget_category_path(category), params: { monthly_target: "150" }

    assert_equal 15_000, category.reload.monthly_target_cents
    assert_equal "user", category.target_set_by
  end

  test "an envelope with history archives instead of deleting; a fresh one deletes" do
    used = @user.budget_categories.create!(name: "Groceries", group: "needs")
    account = @user.spending_accounts.create!(name: "Checking", kind: "checking")
    SpendingTransaction.create!(user_id: @user.id, spending_account_id: account.id,
      occurred_on: Date.current, amount_cents: -1_000, descriptor: "SAFEWAY",
      budget_category_id: used.id, fingerprint: "t-#{SecureRandom.hex(4)}", source: "statement")
    fresh = @user.budget_categories.create!(name: "Fun money", group: "wants")

    delete budget_category_path(used)
    delete budget_category_path(fresh)

    assert used.reload.archived?
    assert_nil BudgetCategory.find_by(id: fresh.id)
  end

  test "re-adding an archived envelope revives it with its history" do
    archived = @user.budget_categories.create!(name: "Groceries", group: "needs", archived_at: Time.current)

    post budget_categories_path, params: { name: "groceries", group: "needs", monthly_target: "400" }

    assert_equal 1, @user.budget_categories.count
    assert_not archived.reload.archived?
    assert_equal 40_000, archived.monthly_target_cents
  end

  test "another user's envelope is out of reach" do
    theirs = users(:two).budget_categories.create!(name: "Theirs", group: "needs")

    patch budget_category_path(theirs), params: { monthly_target: "1" }

    assert_response :not_found
    assert_nil theirs.reload.monthly_target_cents
  end
end
