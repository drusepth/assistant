class PhotoPeopleController < ApplicationController
  def create
    photo = Current.user.photos.find(params[:photo_id])
    person = Person.visible_to(Current.user).find(params[:person_id])
    photo.photo_people.find_or_create_by(person: person)

    redirect_back fallback_location: photo, notice: "Tagged #{person.name}."
  end

  def destroy
    tag = PhotoPerson.joins(:photo).where(photos: { user_id: Current.user.id }).find(params[:id])
    tag.destroy!

    redirect_back fallback_location: tag.photo, notice: "Tag removed."
  end
end
