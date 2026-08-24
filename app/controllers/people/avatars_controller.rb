# Removing a contact's photo (D-contact-photos). Its own route rather than a
# checkbox on the form, mirroring the member avatar's PATCH /avatar: the
# contact is always one of your own (set_own_person, not visible_to), so a
# person shared with you keeps the face their owner gave them.
class People::AvatarsController < ApplicationController
  def destroy
    person = Current.user.people.find(params[:person_id])
    person.avatar.purge_later
    redirect_to edit_person_path(person), notice: "Photo removed."
  end
end
