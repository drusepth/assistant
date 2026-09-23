# The kitchen's food catalog (D-food-catalog): what the model filed, and the
# household's corrections — a merge, a rename, a moved aisle, an allergen.
# Corrections are the household's own rules, and anyone who cooks here can
# make them, the same as anything else in the kitchen.
class FoodsController < ApplicationController
  include KitchenScoped

  before_action :set_food, only: %i[ edit update merge ]

  def index
    @catalog = Foods::Catalog.new(@kitchen)
    @foods = @catalog.visible_foods(Current.user).includes(:kind_of).order(:name).to_a
    @groups = helpers.group_by_aisle(@foods, @kitchen, &:aisle)
    ResolveFoodsJob.enqueue(@kitchen) if @catalog.unresolved?
  end

  def edit
    @others = Foods::Catalog.new(@kitchen).visible_foods(Current.user).where.not(id: @food.id).order(:name)
  end

  def update
    attributes = params.expect(food: [ :name, :aisle, :default_location, :kind_of_id, :staple, allergens: [] ])
    attributes[:kind_of_id] = nil unless @kitchen.foods.exists?(id: attributes[:kind_of_id])

    if @food.update(attributes)
      kitchen_changed!
      redirect_to kitchen_foods_path(@kitchen), notice: "#{@food.name} saved."
    else
      @others = @kitchen.foods.where.not(id: @food.id).order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  # "These are the same" — the household's rule, carried forward by the
  # aliases to every future line.
  def merge
    target = @kitchen.foods.find(params[:target_id])
    @food.merge_into!(target)
    kitchen_changed!
    redirect_to kitchen_foods_path(@kitchen), notice: "#{@food.name} is now #{target.name}."
  rescue ArgumentError => e
    redirect_to edit_kitchen_food_path(@kitchen, @food), alert: e.message
  end

  # Up or down one place in this household's walk through the store.
  def move_aisle
    order = @kitchen.aisles_in_order
    index = order.index(params[:aisle].to_s)
    if index
      swap = params[:direction] == "up" ? index - 1 : index + 1
      order[index], order[swap] = order[swap], order[index] if swap.between?(0, order.size - 1)
      @kitchen.update!(aisle_order: order)
      kitchen_changed!
    end
    redirect_to kitchen_foods_path(@kitchen, anchor: "aisles")
  end

  private
    def set_food
      @food = @kitchen.foods.find(params[:id])
    end
end
