# A kitchen's lists (D-kitchen). The show page is the in-store view — the
# screen this whole section is most used on, built for one thumb in a
# bad-signal aisle.
class ShoppingListsController < ApplicationController
  include KitchenScoped

  before_action :set_list, only: %i[ show update destroy ]

  def show
    @lists = @kitchen.shopping_lists.ordered
    @open_items = @list.open_items.includes(:added_by, :recipe)
    @basket_items = @list.basket_items.includes(:checked_by)
  end

  def create
    list = @kitchen.shopping_lists.new(name: params.dig(:shopping_list, :name).presence || ShoppingList::DEFAULT_NAME,
      position: (@kitchen.shopping_lists.maximum(:position) || 0) + 1)

    if list.save
      kitchen_changed!
      redirect_to kitchen_shopping_list_path(@kitchen, list)
    else
      redirect_back fallback_location: food_path, alert: list.errors.full_messages.to_sentence
    end
  end

  def update
    if @list.update(params.expect(shopping_list: [ :name ]))
      kitchen_changed!
      redirect_to kitchen_shopping_list_path(@kitchen, @list), notice: "List renamed."
    else
      redirect_to kitchen_shopping_list_path(@kitchen, @list), alert: @list.errors.full_messages.to_sentence
    end
  end

  def destroy
    @list.destroy!
    kitchen_changed!
    redirect_to food_path, notice: "#{@list.name} deleted."
  end

  private
    def set_list
      @list = @kitchen.shopping_lists.find(params[:id])
    end
end
