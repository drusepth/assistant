class RecipesController < ApplicationController
  before_action :set_own_recipe,
    only: %i[ edit update destroy cook add_to_book remove_from_book retry_import confirm_import attach_photo ]

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

    @sort = Recipe::SORTS.key?(params[:sort]) ? params[:sort] : "title"
    @recipes = scope.sorted_by(@sort)
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
      # The dish photo you already took: attaching re-points the same blob.
      @recent_photos = Current.user.photos.ingest_ready.with_attached_image
        .order(taken_at: :desc).limit(8)
    end
  end

  def new
    @recipe = Current.user.recipes.new(servings: 4)
  end

  # Paste-import (RECIPES_PLAN §5.1). Nobody retypes a recipe: the honest
  # capture is a link or a blob of pasted page.
  def new_import
    @profile = Current.user.household.model_profile
  end

  def create_import
    url = params[:source_url].to_s.strip
    text = params[:source_text].to_s.strip

    if url.blank? && text.blank?
      return redirect_to import_recipes_path, alert: "Paste a recipe, or give a link to one."
    end
    if url.present? && !url.match?(%r{\Ahttps?://\S+\z})
      return redirect_to import_recipes_path, alert: "That doesn't look like a link — it needs to start with http:// or https://."
    end

    # Our own envelope — pasted JSON, or the share link someone sent, which
    # we ask for as JSON before treating it as a page (D-share-link). Either
    # way it lands with no model call and nothing to review.
    payload = Recipes::Payload.parse(text) || payload_behind(url)
    return land_payload(payload) if payload

    recipe = Current.user.recipes.create!(
      title: placeholder_title(url), source_url: url.presence, import_source: text.presence
    )
    recipe.enqueue_import!
    redirect_to recipe
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
    # Editing an imported recipe *is* reviewing it — the banner's job is
    # done once the cook has been through it.
    @recipe.import_status = nil if @recipe.import_imported?

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

  def retry_import
    @recipe.enqueue_import!
    redirect_to @recipe, notice: "Reading it again — check back in a moment."
  end

  def confirm_import
    @recipe.update!(import_status: nil)
    redirect_to @recipe, notice: "Filed."
  end

  # One source of truth for the dish photo: attaching one of your own
  # Photos re-points the same blob rather than copying the bytes.
  def attach_photo
    photo = Current.user.photos.find(params[:photo_id])
    return redirect_to @recipe, alert: "That photo isn't ready yet." unless photo.image.attached?

    @recipe.image.attach(photo.image.blob)
    redirect_to @recipe, notice: "Photo added."
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

    # A link of ours (/s/<token>) answers with JSON; anything else, or an
    # unreachable one, quietly falls through to the ordinary import.
    def payload_behind(url)
      return nil unless url.match?(%r{/s/[A-Za-z0-9_-]{8,}\z})

      Recipes::Payload.parse(Web::Fetch.text("#{url}.json").text)
    rescue Web::Fetch::Error
      nil
    end

    def land_payload(payload)
      recipes = payload.recipes.map { |attributes| Current.user.recipes.create!(attributes) }

      if payload.book_title.present?
        book = Current.user.recipe_books.create!(title: payload.book_title, description: payload.book_description)
        recipes.each { |recipe| book.recipe_book_entries.create!(recipe: recipe) }
        redirect_to book, notice: "#{recipes.size} #{"recipe".pluralize(recipes.size)} added to your box."
      else
        redirect_to recipes.first, notice: "Added to your box."
      end
    end

    def placeholder_title(url)
      host = URI(url).host if url.present?
      host.present? ? "Importing from #{host.delete_prefix("www.")}…" : "Importing…"
    rescue URI::InvalidURIError
      "Importing…"
    end

    def recipe_params
      params.expect(recipe: [ :title, :description, :directions, :notes, :ingredients_text,
        :source_name, :source_url, :servings, :prep_minutes, :cook_minutes, :favorite, :image,
        section_ids: [] ])
    end
end
