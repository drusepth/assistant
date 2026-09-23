# "Add to list" on a recipe page: its ingredients onto the viewer's kitchen
# list, scaled to the servings on screen, each line remembering which
# recipe it's for.
module Recipes
  class ListAdditionsController < ApplicationController
    def create
      recipe = Recipe.visible_to(Current.user).find(params[:recipe_id])
      kitchen = Kitchens::Current.for(Current.user)
      list = kitchen.shopping_lists.find_by(id: params[:shopping_list_id]) || ShoppingList.default_for(kitchen)
      servings = params[:servings].presence&.to_i&.clamp(1, 100)

      rows = Kitchens::RecipeNeeds.new(recipe, factor: recipe.scale_factor(servings), kitchen: kitchen).rows
      added = ShoppingLists::Add.new(list, by: Current.user).rows(rows, recipe: recipe)

      redirect_back fallback_location: recipe_path(recipe),
        notice: added.any? ? "#{helpers.pluralize(added.size, "thing")} on #{list.name}." : "Nothing to add."
    end
  end
end
