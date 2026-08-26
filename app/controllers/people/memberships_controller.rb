# Group membership (D-people-circles): the verb the People page was missing.
# Scoped to People's own custom lenses — this is not a general "tag anything
# into any section" endpoint, and the section picker on the item forms
# remains the general one.
class People::MembershipsController < ApplicationController
  before_action :set_group

  def create
    person = People::Membership.add(Current.user, @group, person_id: params[:person_id], name: params[:name])
    return back_to_group(alert: "Pick someone, or name someone new.") if person.nil?

    back_to_group(notice: "#{person.name} is in #{@group.name}.")
  end

  def destroy
    person = People::Membership.remove(Current.user, @group, person_id: params[:person_id])
    return back_to_group(alert: "Couldn't find that person.") if person.nil?

    back_to_group(notice: "#{person.name} is no longer in #{@group.name}. They're still in your Address Book.")
  end

  private
    def set_group
      @group = Section.custom.where(parent: Section.find_by!(slug: "people")).find(params[:section_id])
    end

    def back_to_group(**flash)
      redirect_back fallback_location: section_path(@group.slug), **flash
    end
end
