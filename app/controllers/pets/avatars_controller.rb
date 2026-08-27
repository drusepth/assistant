# Removing a pet's photo — its own route rather than a checkbox on the form,
# mirroring the contact's (D-contact-photos). Always one of your own pets, so
# a pet shared with you keeps the face her owner gave her.
class Pets::AvatarsController < ApplicationController
  def destroy
    pet = Current.user.pets.find(params[:pet_id])
    pet.avatar.purge_later
    redirect_to edit_pet_path(pet), notice: "Photo removed."
  end
end
