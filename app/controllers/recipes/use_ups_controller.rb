module Recipes
  # "Anything used up?" after cooking — the kitchen rows the recipe drew on,
  # and the ones ticked come out.
  class UseUpsController < ApplicationController
    before_action :set_recipe_and_kitchen

    def new
      @rows = Recipes::UseUp.new(@recipe, @kitchen).rows
      redirect_to @recipe if @rows.empty?
    end

    def create
      allowed = Recipes::UseUp.new(@recipe, @kitchen).rows.map(&:id)
      removed = @kitchen.pantry_items.where(id: Array(params[:pantry_item_ids]).map(&:to_i) & allowed).destroy_all
      @kitchen.broadcast_change if removed.any?

      redirect_to @recipe, notice: removed.any? ? "#{helpers.pluralize(removed.size, "thing")} out of the kitchen." : nil
    end

    private
      def set_recipe_and_kitchen
        @recipe = Recipe.visible_to(Current.user).find(params[:recipe_id])
        @kitchen = Kitchens::Current.for(Current.user)
      end
  end
end
