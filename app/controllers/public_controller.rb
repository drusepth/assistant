# The public read page behind a share link (D-share-link): the only
# unauthenticated read path in the app. It renders on its own bare layout —
# no navigation, no section chips, no email addresses, no way further in —
# and it renders nothing at all unless the token names a live link to an
# allowlisted subject.
class PublicController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  # The token is the whole authorization, so the endpoint gets the same
  # treatment as the app's other token doors (invitation accept, vault
  # unlock). 24 characters is far past brute force; this is belt-and-braces
  # and sits well above what a family reading a book generates.
  rate_limit to: 60, within: 1.minute, with: -> { render :gone, status: :too_many_requests }

  # A forwarded link shouldn't become a search result.
  before_action { response.set_header("X-Robots-Tag", "noindex, nofollow") }

  def show
    @link = ShareLink.live.find_by(token: params[:token])
    return gone if @link.nil?

    @owner = @link.user
    @link.record_view!

    case @link.subject
    when Recipe then show_recipe(@link.subject)
    when RecipeBook then show_book(@link.subject)
    else gone
    end
  end

  private
    def show_recipe(recipe)
      @recipe = recipe
      @servings = params[:servings].presence&.to_i&.clamp(1, 100) || @recipe.servings
      @factor = @recipe.scale_factor(@servings)
      render :recipe
    end

    # One link covers a book *and* the recipes in it: ?recipe=<id> opens one
    # of them under the same token. The owner guard is the album clause's
    # rule in Ruby — a book can only ever publish its owner's recipes, so a
    # later collaborative book (Q-recipe-collab) can't publish a
    # contributor's.
    def show_book(book)
      @book = book
      @recipes = book.recipes.where(user_id: book.user_id)
        .with_attached_image.order(Arel.sql("LOWER(recipes.title)"))

      if params[:recipe].present?
        recipe = @recipes.find_by(id: params[:recipe])
        return gone if recipe.nil?

        show_recipe(recipe)
      else
        render :book
      end
    end

    def gone
      render :gone, status: :not_found
    end
end
