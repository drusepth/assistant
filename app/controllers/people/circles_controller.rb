# The circle (D-people-dashboard): the People page is about relationships the user is
# tending, marked explicitly — from the section page's capture card or the
# person page. Flagging is intent, never obligation; unflagging just takes
# someone off the dashboard, the Address Book keeps them.
class People::CirclesController < ApplicationController
  include PersonPicked

  def create
    person = People::Picker.for_circle(Current.user).resolve(person_id: params[:person_id], name: params[:name])
    raise ActiveRecord::RecordNotFound if person.nil? && params[:person_id].present?
    return redirect_back_to_people(alert: "Pick someone, or name someone new.") if person.nil?

    created = person.previously_new_record?
    person.enqueue_auto_sort! if created
    person.update!(keep_in_touch: true)

    person_picked(person, created: created, notice: "#{person.name} added to your circle.",
      undo_url: people_circle_path(person_id: person.id), fallback: section_path("people")) do
      circle = people_cards.first
      [ card_summary_stream(circle),
        turbo_stream.replace("reach-out", partial: "sections/reach_out",
          locals: { reach_out: circle.members.first(Sections::Panels::People::REACH_OUT) }) ]
    end
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
