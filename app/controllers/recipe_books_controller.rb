class RecipeBooksController < ApplicationController
  before_action :set_own_book, only: %i[ edit update destroy add_recipes remove_recipes reorder ]

  def index
    @books = RecipeBook.visible_to(Current.user).includes(:user, recipes: { image_attachment: :blob })
      .order(:title)
  end

  def show
    @book = RecipeBook.visible_to(Current.user).find(params[:id])
    @owned = @book.user_id == Current.user.id
    # A book has a running order the owner chose — a spring book reads
    # front to back, not alphabetically.
    @recipes = @book.recipes.visible_to(Current.user).includes(:sections, :user)
      .with_attached_image.merge(RecipeBookEntry.order(:position, :id))
    if @owned
      @available_recipes = Current.user.recipes.where.not(id: @book.recipe_ids).order(:title)
      @share_links = @book.share_links.order(created_at: :desc)
    end
  end

  def new
    @book = Current.user.recipe_books.new
  end

  def create
    @book = Current.user.recipe_books.new(book_params)

    if @book.save
      redirect_to @book, notice: "Book created — now fill it with recipes."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
      redirect_to @book, notice: "Book updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Deleting removes the container only — never the recipes in it.
  def destroy
    @book.destroy!
    redirect_to recipe_books_path, notice: "Book deleted. Its recipes are still in your box."
  end

  def add_recipes
    recipes = Current.user.recipes.where(id: recipe_id_params).where.not(id: @book.recipe_ids)
    position = @book.recipe_book_entries.maximum(:position) || 0
    recipes.each { |recipe| @book.recipe_book_entries.create!(recipe: recipe, position: position += 1) }
    @book.touch if recipes.any?

    redirect_back fallback_location: @book,
      notice: "#{recipes.size} #{"recipe".pluralize(recipes.size)} added to #{@book.title}."
  end

  def remove_recipes
    removed = @book.recipe_book_entries.where(recipe_id: recipe_id_params).destroy_all

    redirect_back fallback_location: @book,
      notice: "#{removed.size} #{"recipe".pluralize(removed.size)} removed from #{@book.title}."
  end

  # Drag-to-reorder: the rows submit in DOM order, so the order *is* the
  # persistence (the settings-page convention).
  def reorder
    recipe_id_params.each_with_index do |recipe_id, index|
      @book.recipe_book_entries.where(recipe_id: recipe_id).update_all(position: index + 1)
    end
    redirect_to @book, notice: "Order saved."
  end

  private
    def set_own_book
      @book = Current.user.recipe_books.find(params[:id])
    end

    def book_params
      params.expect(recipe_book: [ :title, :description, :cover_recipe_id ])
    end

    def recipe_id_params
      Array(params[:recipe_ids]).reject(&:blank?)
    end
end
