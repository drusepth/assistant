class AddHeadingToRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    # "For the sauce:" is not an ingredient (D-recipe-primitive): almost
    # every recipe with more than one component has these lines, and left
    # unmarked they became pseudo-ingredients that would pollute the
    # item_key column the pantry match is built on.
    add_column :recipe_ingredients, :heading, :boolean, null: false, default: false
  end
end
