# The money side of a pet (D-pet-food-shelf): the envelope her spending files
# into, and the merchant rules that keep it filing itself.
#
# Both are ordinary Money objects — a BudgetCategory and a SpendingRule — made
# from the pet's page because that's where you're standing when you think of
# it. Nothing here is pet-specific except the name.
class PetBudgetsController < ApplicationController
  before_action :set_pet

  # Creates the Pets envelope if it isn't there, and offers the food shelf's
  # arithmetic as its target — never over a target the user set by hand (D16).
  def create
    category = Current.user.budget_categories.active.find_by("LOWER(name) = ?", Pets::CostOfCare::CATEGORY_NAME.downcase)
    category ||= Current.user.budget_categories.create!(name: Pets::CostOfCare::CATEGORY_NAME, group: "needs")

    planned = planned_food_cents
    if planned&.positive? && !category.target_hand_set?
      category.update!(monthly_target_cents: planned, target_set_by: "tool")
      return redirect_to @pet, notice: "Pets envelope ready, with #{helpers.money_amount(planned)} a month from the food shelf. Change it any time."
    end

    redirect_to @pet, notice: "Pets envelope ready. Set a target on the Budget page whenever you like."
  end

  # "Always file Chewy under Pets" — the same rule object the ledger's
  # recategorize button writes, made from the page where you know the answer.
  def update
    matcher = params[:matcher].to_s.strip
    category = Current.user.budget_categories.active.find_by("LOWER(name) = ?", Pets::CostOfCare::CATEGORY_NAME.downcase)
    return redirect_to(@pet, alert: "Make the Pets envelope first.") if category.nil?
    return redirect_to(@pet, alert: "Which shop? Type the name as it appears on the statement.") if matcher.blank?

    rule = Current.user.spending_rules.create_with(budget_category: category).find_or_create_by(matcher: matcher.downcase)
    rule.update!(budget_category: category) unless rule.budget_category_id == category.id
    Spending::Categorize.new(user: Current.user).apply_rule(rule)

    redirect_to @pet, notice: "Spending from “#{rule.matcher}” files under Pets from now on."
  end

  private
    def set_pet
      @pet = Current.user.pets.find(params[:pet_id])
    end

    # Every pet's current diet, not just this one's: the envelope is one line
    # in a household budget, and it feeds all of them.
    def planned_food_cents
      totals = Current.user.pets.active.filter_map { |pet| Pets::FoodShelf.new(pet).monthly_cost_cents }
      totals.any? ? totals.sum : nil
    end
end
