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
    when Album then show_album(@link.subject)
    when Pet then show_vaccine_record(@link.subject)
    else gone
    end
  end

  # A certificate attached to one of a shared pet's doses, streamed through
  # the token (D-pet-vaccinations) — never a permanent blob URL, so the file
  # stops being reachable the moment the link is revoked or expires. Only a
  # document the pet's owner owns, attached to a dose of *this* pet.
  def certificate
    link = ShareLink.live.find_by(token: params[:token])
    return gone unless link&.subject.is_a?(Pet)

    dose = link.subject.pet_vaccinations.find_by(id: params[:id])
    document = dose&.document
    return gone unless document&.file&.attached? && document.user_id == link.user_id

    send_data document.file.download, filename: document.file.filename.to_s,
      type: document.file.content_type, disposition: "inline"
  end

  private
    # The take-it-with-you format (D-share-link): the same token, asked for
    # as JSON, is a recipe another instance can import with no model call
    # and no account anywhere.
    def render_payload(payload)
      render json: payload
    end

    def show_recipe(recipe)
      return render_payload(Recipes::Payload.for_recipe(recipe)) if request.format.json?

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

      if request.format.json?
        return render_payload(Recipes::Payload.for_book(book, @recipes.includes(:recipe_ingredients)))
      end

      if params[:recipe].present?
        recipe = @recipes.find_by(id: params[:recipe])
        return gone if recipe.nil?

        show_recipe(recipe)
      else
        render :book
      end
    end

    # An album travels like a book: the container, and under the same token
    # its own contents — never a photo its owner doesn't own, and never the
    # original bytes. The grid and the single view render the same stripped
    # WEBP variants a household grantee sees, so a shared photo carries no
    # EXIF and no coordinates out of the house.
    def show_album(album)
      # Only recipes have a take-it-with-you envelope; an album's answer to
      # "as JSON" is nothing.
      return gone if request.format.json?

      @album = album
      @photos = album.photos.where(user_id: album.user_id)
        .with_attached_image.order(taken_at: :desc, id: :desc)

      if params[:photo].present?
        @photo = @photos.find_by(id: params[:photo])
        return gone if @photo.nil?

        index = @photos.index(@photo)
        @previous_photo = index.positive? ? @photos[index - 1] : nil
        @next_photo = @photos[index + 1]
        render :photo
      else
        render :album
      end
    end

    # A pet's link shows her vaccine one-sheet and nothing else of hers — the
    # same partial the owner prints, so the two cannot drift apart.
    def show_vaccine_record(pet)
      return gone if request.format.json?

      @pet = pet
      @status = Pets::VaccineStatus.new(pet, viewer: pet.user)
      render :vaccine_record
    end

    def gone
      return head :not_found if request.format.json?

      render :gone, status: :not_found
    end
end
