class PhotoPeopleController < ApplicationController
  def create
    photo = Current.user.photos.find(params[:photo_id])
    # Typing a name nobody has makes the contact (D-person-picker) — the
    # photo is often where you first think to write someone down.
    person = People::Picker.for_photo(Current.user, photo).resolve(person_id: params[:person_id], name: params[:name])
    raise ActiveRecord::RecordNotFound if person.nil? && params[:person_id].present?
    return redirect_back(fallback_location: photo, alert: "Pick someone, or name someone new.") if person.nil?

    photo.photo_people.find_or_create_by(person: person)

    redirect_back fallback_location: photo, notice: "Tagged #{person.name}."
  end

  def destroy
    tag = PhotoPerson.joins(:photo).where(photos: { user_id: Current.user.id }).find(params[:id])
    tag.destroy!

    redirect_back fallback_location: tag.photo, notice: "Tag removed."
  end
end
