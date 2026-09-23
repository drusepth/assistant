# Lines on a kitchen's list. Check and uncheck answer a script with an empty
# 204 — the row already moved on the phone before the request left
# (the in-store list's optimistic taps) — and a plain form with a redirect.
class ShoppingListItemsController < ApplicationController
  include KitchenScoped

  before_action :set_list
  before_action :set_item, only: %i[ update destroy check uncheck ]

  def create
    added = @list.add_lines(params[:lines].to_s, by: Current.user)

    if added.any?
      redirect_back fallback_location: kitchen_shopping_list_path(@kitchen, @list)
    else
      redirect_back fallback_location: kitchen_shopping_list_path(@kitchen, @list),
        alert: "Nothing to add — one thing per line, like “2 tins chickpeas”."
    end
  end

  # Retyping a line re-parses it, so "3 lemons" corrects the amount too.
  def update
    attributes = Recipes::Parse.line_attributes(params[:line].to_s)
    if params[:line].present? && !attributes[:heading]
      @item.update!(attributes.slice(:item, :item_key, :quantity, :unit, :note)
        .merge(note: attributes[:note].to_s.truncate(200).presence))
      kitchen_changed!
    end
    redirect_back fallback_location: kitchen_shopping_list_path(@kitchen, @list)
  end

  def destroy
    @item.destroy!
    kitchen_changed!
    respond_to_tap
  end

  def check
    @item.check!(by: Current.user) unless @item.checked?
    kitchen_changed!
    respond_to_tap
  end

  def uncheck
    @item.uncheck!
    kitchen_changed!
    respond_to_tap
  end

  private
    def set_list
      @list = @kitchen.shopping_lists.find(params[:shopping_list_id])
    end

    def set_item
      @item = @list.items.find(params[:id])
    end

    def respond_to_tap
      if request.headers["X-Optimistic"].present?
        head :no_content
      else
        redirect_back fallback_location: kitchen_shopping_list_path(@kitchen, @list)
      end
    end
end
