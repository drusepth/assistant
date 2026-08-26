# The memorial album (D-pet-primitive). Her photos are already gathered by
# her lens, so the album is one button — offered only once she is gone, never
# as a prompt, and never as something the app does on its own.
class PetAlbumsController < ApplicationController
  def memorial
    pet = Current.user.pets.find(params[:pet_id])
    photos = Current.user.photos.in_section(pet.section).order(:taken_at)
    return redirect_to(pet, alert: "No photos are tagged #{pet.name} yet.") if photos.empty?

    album = Current.user.albums.find_or_create_by!(title: pet.name) do |new_album|
      new_album.description = memorial_description(pet)
    end
    photos.where.not(id: album.photo_ids).each { |photo| album.album_photos.create!(photo: photo) }

    redirect_to album, notice: "#{pet.name}'s album is ready."
  end

  private
    def memorial_description(pet)
      years = [ pet.born_on&.year, pet.died_on&.year ].compact
      years.size == 2 ? "#{pet.name}, #{years.join("–")}." : pet.name
    end
end
