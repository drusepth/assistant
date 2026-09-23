# The Breed box's "not sure?" helper (Pets::BreedGuess): a photo in, up to
# three suggestions out, rendered under the box for a tap to fill it. It
# answers the form and saves nothing — not the pet, not the photo — so it
# serves a pet that doesn't exist yet as well as one that does.
class Pets::BreedGuessesController < ApplicationController
  def create
    profile = Pets::BreedGuessesController.profile_for(Current.user)
    raise Llm::Error, "Guessing a breed needs a model that can see images" unless profile

    image = image_bytes
    raise Llm::Error, "Choose a photo first" unless image

    result = Pets::BreedGuess.new(species: params[:species].to_s, image: image, profile: profile).call
    render_result(result: result)
  rescue Llm::Error => error
    render_result(error: "Couldn't tell — #{error.message.chomp('.')}. You can still type it in.")
  end

  # The same gate every image-reading feature uses: a model the admin has
  # declared vision-capable. Without one the helper isn't offered.
  def self.profile_for(user)
    profile = user.household.model_profile
    profile if profile&.configured? && profile.vision?
  end

  private
    def image_bytes
      if (upload = params[:photo]).respond_to?(:tempfile)
        unless Avatarable::AVATAR_CONTENT_TYPES.include?(upload.content_type) && upload.size <= Avatarable::AVATAR_MAX_BYTES
          raise Llm::Error, "That file isn't a photo the app can read (PNG, JPEG, WebP or GIF, up to #{Avatarable::AVATAR_MAX_BYTES / 1.megabyte} MB)"
        end
        Pets::BreedGuess.image_bytes(upload: upload)
      elsif params[:photo_id].present?
        photo = Photo.visible_to(Current.user).find_by(id: params[:photo_id])
        Pets::BreedGuess.image_bytes(attachment: photo.image) if photo&.image&.attached?
      elsif params[:pet_id].present?
        pet = Pet.visible_to(Current.user).find_by(id: params[:pet_id])
        Pets::BreedGuess.image_bytes(attachment: pet.avatar) if pet&.avatar_ready?
      end
    rescue Vips::Error, ActiveStorage::InvariableError
      raise Llm::Error, "That file couldn't be opened as an image"
    end

    def render_result(**locals)
      render turbo_stream: turbo_stream.update("breed_guess_result", partial: "pets/breed_guess_result", locals: locals)
    end
end
