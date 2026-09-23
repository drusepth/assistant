# The circle (D-people-dashboard): the People page is about relationships the user is
# tending, marked explicitly — from the section page's capture card or the
# person page. Flagging is intent, never obligation; unflagging just takes
# someone off the dashboard, the Address Book keeps them.
class People::CirclesController < ApplicationController
  def create
    person = People::Picker.for_circle(Current.user).resolve(person_id: params[:person_id], name: params[:name])
    raise ActiveRecord::RecordNotFound if person.nil? && params[:person_id].present?
    return redirect_back_to_people(alert: "Pick someone, or name someone new.") if person.nil?

    person.enqueue_auto_sort! if person.previously_new_record?
    person.update!(keep_in_touch: true)
    redirect_back_to_people(notice: "#{person.name} added to your circle.")
  end

  def destroy
    person = Current.user.people.find(params[:person_id])
    person.update!(keep_in_touch: false)
    redirect_back_to_people(notice: "#{person.name} removed from your circle. They're still in your Address Book.")
  end

  private
    def redirect_back_to_people(**flash)
      redirect_back fallback_location: section_path("people"), **flash
    end
end
