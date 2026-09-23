# What's in the kitchen (D-kitchen): three tabs — fridge, freezer, cupboard —
# each soonest-to-expire first. Rows of the kitchen, so anyone who cooks
# here can add, move, and mark things used up.
class PantryItemsController < ApplicationController
  include KitchenScoped

  before_action :set_item, only: %i[ update destroy move add_to_list ]

  def index
    @location = Food::LOCATIONS.key?(params[:location]) ? params[:location] : "fridge"
    @counts = @kitchen.pantry_items.group(:location).count
    @items = @kitchen.pantry_items.in_location(@location).by_expiry.includes(:food, :added_by)
  end

  def create
    location = Food::LOCATIONS.key?(params[:location]) ? params[:location] : "fridge"
    added = Kitchens::Pantry.new(@kitchen, by: Current.user).add_lines(params[:lines].to_s, location: location)

    redirect_back fallback_location: kitchen_pantry_items_path(@kitchen, location: location),
      alert: (added.empty? ? "Nothing to add — one thing per line, like “rice, half a bag”." : nil)
  end

  def update
    @item.update!(params.expect(pantry_item: [ :quantity_note, :expires_on, :opened_on ]))
    kitchen_changed!
    redirect_back fallback_location: kitchen_pantry_items_path(@kitchen, location: @item.location)
  end

  # Used up.
  def destroy
    @item.destroy!
    kitchen_changed!
    redirect_back fallback_location: kitchen_pantry_items_path(@kitchen, location: @item.location)
  end

  def move
    @item.move_to!(params[:location]) if Food::LOCATIONS.key?(params[:location])
    kitchen_changed!
    redirect_back fallback_location: kitchen_pantry_items_path(@kitchen, location: @item.location)
  end

  def add_to_list
    list = @kitchen.shopping_lists.find_by(id: params[:shopping_list_id]) || ShoppingList.default_for(@kitchen)
    ShoppingLists::Add.new(list, by: Current.user).rows([ { item: @item.item, item_key: @item.item_key } ])
    redirect_back fallback_location: kitchen_pantry_items_path(@kitchen, location: @item.location),
      notice: "#{@item.item} is on #{list.name}."
  end

  private
    def set_item
      @item = @kitchen.pantry_items.find(params[:id])
    end
end
