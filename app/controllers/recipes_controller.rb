class RecipesController < ApplicationController
  before_action :set_own_recipe, only: %i[ edit update destroy cook add_to_book remove_from_book ]

  def index
    scope = Recipe.visible_to(Current.user).includes(:sections, :user).with_attached_image

    if params[:q].present?
      @query = params[:q]
      scope = scope.search(@query)
    end
    if params[:section].present?
      @section = Section.find_by!(slug: params[:section])
      scope = scope.in_section([ @section.id, *@section.children.ids ])
    end
    scope = scope.favorites if params[:favorites].present?

    @recipes = scope.order(Arel.sql("LOWER(recipes.title)"))
    @books = RecipeBook.visible_to(Current.user).order(:title)
  end

  def show
    @recipe = Recipe.visible_to(Current.user).includes(:recipe_ingredients, :sections).find(params[:id])
    @owned = @recipe.user_id == Current.user.id
    # Scaling is a link, not JavaScript: ?servings=8 re-renders the
    # quantities, survives a refresh, and works with JS off.
    @servings = params[:servings].presence&.to_i&.clamp(1, 100) || @recipe.servings
    @factor = @recipe.scale_factor(@servings)
    @books = @recipe.recipe_books.visible_to(Current.user).order(:title)
    if @owned
      @available_books = Current.user.recipe_books.where.not(id: @recipe.recipe_book_ids).order(:title)
      @share_links = @recipe.share_links.order(created_at: :desc)
    end
  end

  def new
    @recipe = Current.user.recipes.new(servings: 4)
  end

  def create
    @recipe = Current.user.recipes.new(recipe_params)

    if @recipe.save
      book = Current.user.recipe_books.find_by(id: params[:recipe_book_id])
      book&.recipe_book_entries&.create(recipe: @recipe)
      redirect_to @recipe, notice: "Recipe saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @recipe.update(recipe_params)
      redirect_to @recipe, notice: "Recipe updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recipe.destroy!
    redirect_to recipes_path, notice: "Recipe deleted."
  end

  # The whole cook log (D-recipe-primitive): one tap, no timers, no streaks.
  def cook
    @recipe.cooked!
    redirect_back fallback_location: @recipe,
      notice: "Logged — #{@recipe.title} #{@recipe.times_cooked == 1 ? "cooked once" : "cooked #{@recipe.times_cooked} times"}."
  end

  def add_to_book
    book = Current.user.recipe_books.find(params[:recipe_book_id])
    book.recipe_book_entries.find_or_create_by!(recipe: @recipe)
    redirect_back fallback_location: @recipe, notice: "Added to #{book.title}."
  end

  def remove_from_book
    book = Current.user.recipe_books.find(params[:recipe_book_id])
    book.recipe_book_entries.where(recipe: @recipe).destroy_all
    redirect_back fallback_location: @recipe, notice: "Removed from #{book.title}."
  end

  private
    def set_own_recipe
      @recipe = Current.user.recipes.find(params[:id])
    end

    def recipe_params
      params.expect(recipe: [ :title, :description, :directions, :notes, :ingredients_text,
        :source_name, :source_url, :servings, :prep_minutes, :cook_minutes, :favorite, :image,
        section_ids: [] ])
    end
end
