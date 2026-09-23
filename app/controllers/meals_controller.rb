# The kitchen's meal plan (D-kitchen): a week at a time, rows anyone who
# cooks here can add, move and clear.
class MealsController < ApplicationController
  include KitchenScoped

  before_action :set_meal, only: %i[ update destroy ]

  def index
    @week_start = week_start
    @days = (@week_start..(@week_start + 6)).to_a
    @meals = @kitchen.meals.between(@days.first..@days.last).in_order.includes(:recipe, :cook).group_by(&:date)
    @recipes = Recipe.visible_to(Current.user).order(:title).pluck(:title, :id)
    @cooks = @kitchen.cooks.order(:name)
    @lists = @kitchen.shopping_lists.ordered
    # A meal can be one of that day's events — the dinner party.
    @events_by_day = Event.visible_to(Current.user)
      .overlapping(@days.first.beginning_of_day..@days.last.end_of_day)
      .order(:starts_at).group_by { |event| event.starts_at.to_date }
  end

  def create
    meal = @kitchen.meals.new(meal_params)
    if meal.save
      kitchen_changed!
      redirect_back fallback_location: kitchen_meals_path(@kitchen, week: meal.date), notice: "#{meal.title} planned for #{meal.date.strftime("%A")}."
    else
      redirect_back fallback_location: kitchen_meals_path(@kitchen), alert: meal.errors.full_messages.to_sentence
    end
  end

  def update
    if @meal.update(meal_params)
      kitchen_changed!
      redirect_back fallback_location: kitchen_meals_path(@kitchen, week: @meal.date)
    else
      redirect_back fallback_location: kitchen_meals_path(@kitchen, week: @meal.date), alert: @meal.errors.full_messages.to_sentence
    end
  end

  def destroy
    @meal.destroy!
    kitchen_changed!
    redirect_back fallback_location: kitchen_meals_path(@kitchen, week: @meal.date)
  end

  def make_list
    start = week_start
    list = @kitchen.shopping_lists.find_by(id: params[:shopping_list_id]) || ShoppingList.default_for(@kitchen)
    result = Kitchens::WeekList.new(@kitchen, list, by: Current.user).call(start..(start + 6))

    notice = if result.meals.zero? then "Nothing new to shop for — every planned recipe is already on a list."
    else "#{helpers.pluralize(result.lines, "thing")} for #{helpers.pluralize(result.meals, "meal")} on #{list.name}."
    end
    redirect_to kitchen_meals_path(@kitchen, week: start), notice: notice
  end

  private
    def set_meal
      @meal = @kitchen.meals.find(params[:id])
    end

    # A recipe you can't see, a cook who doesn't cook here, or an event you
    # can't see is dropped rather than planned.
    def meal_params
      attributes = params.expect(meal: [ :date, :slot, :title, :recipe_id, :servings, :cook_id, :event_id ])
      if attributes.key?(:recipe_id)
        attributes[:recipe_id] = Recipe.visible_to(Current.user).find_by(id: attributes[:recipe_id])&.id
      end
      if attributes.key?(:cook_id)
        attributes[:cook_id] = @kitchen.cooks.find_by(id: attributes[:cook_id])&.id
      end
      if attributes.key?(:event_id)
        attributes[:event_id] = Event.visible_to(Current.user).find_by(id: attributes[:event_id])&.id
      end
      attributes[:servings] = attributes[:servings].presence
      attributes
    end

    # Weeks start on Monday, like the calendar.
    def week_start
      Date.parse(params[:week].to_s).beginning_of_week
    rescue Date::Error
      Date.current.beginning_of_week
    end
end
