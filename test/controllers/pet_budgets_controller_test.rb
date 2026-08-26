require "test_helper"

class PetBudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @rex = create_pet
    @rex.pet_foods.create!(name: "Adult chicken", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12_000, package_cost_cents: 5_400, started_on: Date.current, opened_on: Date.current)
  end

  test "the envelope takes the food shelf's arithmetic as its target" do
    post pet_budget_path(@rex)

    category = users(:one).budget_categories.sole
    assert_equal "Pets", category.name
    assert_equal "needs", category.group
    assert_equal 4_109, category.monthly_target_cents
    assert_equal "tool", category.target_set_by
  end

  test "a target the user set by hand is never written over" do
    users(:one).budget_categories.create!(name: "Pets", group: "needs",
      monthly_target_cents: 9_000, target_set_by: "user")

    post pet_budget_path(@rex)
    assert_equal 9_000, users(:one).budget_categories.sole.monthly_target_cents
  end

  test "a merchant rule files pet spending under Pets from now on" do
    post pet_budget_path(@rex)
    patch pet_budget_path(@rex), params: { matcher: "Chewy" }

    rule = users(:one).spending_rules.sole
    assert_equal "chewy", rule.matcher
    assert_equal "Pets", rule.budget_category.name
  end

  test "a rule with no envelope, or no merchant, is refused with a reason" do
    patch pet_budget_path(@rex), params: { matcher: "Chewy" }
    assert_equal "Make the Pets envelope first.", flash[:alert]

    post pet_budget_path(@rex)
    patch pet_budget_path(@rex), params: { matcher: "  " }
    assert_match "Which shop?", flash[:alert]
    assert_empty users(:one).spending_rules
  end
end
