# What can I make, what uses up what's going off, and what to buy
# (D-food-suggestions). The lists are arithmetic and arrive with the page;
# tonight's pick, with a model, arrives a moment later over Turbo.
class IdeasController < ApplicationController
  include KitchenScoped

  def show
    @ideas = Kitchens::Ideas.new(@kitchen, Current.user)
    @ready = @ideas.ready_to_make(limit: 24)
    @use_it_up = @ideas.use_it_up(limit: 12)
    @unlock = @ideas.buy_to_unlock
    @pick = IdeasPickJob.fetch(@kitchen, Current.user)
    @pick_recipe = Recipe.visible_to(Current.user).find_by(id: @pick["recipe_id"]) if @pick.is_a?(Hash) && @pick["recipe_id"]
    @diet_notes = @kitchen.diners.filter_map { |diner| "#{diner.name}: #{diner.diet_note}" if diner.diet_note.present? }
    @model = Foods::Catalog.new(@kitchen).model?
  end
end
