# The circle (D38): the People page is about relationships the user is
# tending, marked explicitly — from the section page's capture card or the
# person page. Flagging is intent, never obligation; unflagging just takes
# someone off the dashboard, the Address Book keeps them.
class People::CirclesController < ApplicationController
  def create
    person =
      if params[:person_id].present?
        Current.user.people.find(params[:person_id])
      elsif params[:name].to_s.squish.present?
        Current.user.people.create!(name: params[:name].to_s.squish).tap(&:enqueue_auto_sort!)
      end
    return redirect_back_to_people(alert: "Pick someone, or name someone new.") if person.nil?

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
