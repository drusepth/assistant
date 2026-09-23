# The person picker's suggestions (D-person-picker): what the combobox shows
# as you type. Answers with option rows rather than JSON so a face renders
# through Ui::AvatarComponent here exactly as it does everywhere else — one
# face, one place (D-user-avatars) — instead of being rebuilt in JavaScript.
#
# `for` names the place the person is going (circle, group, photo), which
# decides the pool and who's already there. It saves nothing.
class People::MatchesController < ApplicationController
  def index
    @query = params[:q].to_s.squish
    picker = picker_for(params[:for])
    @people = picker.matches(@query)
    # Offer "add as new" unless the typed name is already someone's —
    # including someone already in the circle, group or photo, who the
    # list leaves out but who still isn't new.
    @offer_new = @query.present? && picker.exact(@query).nil?
    render layout: false
  end

  private
    def picker_for(place)
      case place
      when "group"
        group = Section.custom.where(parent: Section.find_by!(slug: "people")).find(params[:section_id])
        People::Picker.for_group(Current.user, group)
      when "photo"
        People::Picker.for_photo(Current.user, Current.user.photos.find(params[:photo_id]))
      else
        People::Picker.for_circle(Current.user)
      end
    end
end
