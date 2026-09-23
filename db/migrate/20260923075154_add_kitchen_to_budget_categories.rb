class AddKitchenToBudgetCategories < ActiveRecord::Migration[8.1]
  def change
    # "This envelope is our food shopping" — the user's own rule, set from
    # the kitchen's settings, so the Food hub can show how the month's
    # grocery money is going without reading category names for meaning.
    add_column :budget_categories, :food_shopping, :boolean, null: false, default: false
  end
end
