# Group membership (D-people-circles): the verb the People page was missing.
# Scoped to People's own custom lenses — this is not a general "tag anything
# into any section" endpoint, and the section picker on the item forms
# remains the general one.
class People::MembershipsController < ApplicationController
  include PersonPicked

  before_action :set_group

  def create
    person = People::Membership.add(Current.user, @group, person_id: params[:person_id], name: params[:name])
    return back_to_group(alert: "Pick someone, or name someone new.") if person.nil?

    person_picked(person, created: person.previously_new_record?, notice: "#{person.name} is in #{@group.name}.",
      undo_url: people_membership_path(section_id: @group.id, person_id: person.id), fallback: section_path(@group.slug)) do
      # Both surfaces a group is added to from: its card on the People
      # page and its own page. The page that isn't open ignores its stream.
      [ card_summary_stream(people_cards.find { |card| card.section == @group }),
        turbo_stream.replace("group-members", partial: "sections/group_members",
          locals: { members: Sections::Panels::PeopleLens.new(section: @group, viewer: Current.user).members, section: @group }) ]
    end
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
