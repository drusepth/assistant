# Who's on the trip (D-trip-companions). The owner manages the list;
# membership is what shares the trip, so this is the owner's call the same
# way an AccessGrant would be.
class TripCompanionsController < ApplicationController
  include TripAccess

  def create
    trip = find_trip_as_owner(params[:trip_id])
    companion = Current.user.household.users.find(params.dig(:trip_membership, :user_id))
    membership = trip.memberships.new(user: companion)
    if membership.save
      redirect_to trip_path(trip, anchor: "travelers"), notice: "#{companion.name} is on the trip."
    else
      redirect_to trip_path(trip, anchor: "travelers"), alert: membership.errors.full_messages.to_sentence
    end
  end

  # The owner removes anyone; a companion can always take themselves off.
  def destroy
    membership = TripMembership.find(params[:id])
    trip = membership.trip
    unless trip.user_id == Current.user.id || membership.user_id == Current.user.id
      raise ActiveRecord::RecordNotFound
    end

    membership.destroy!
    if membership.user_id == Current.user.id && trip.user_id != Current.user.id
      redirect_to section_path("travel"), notice: "You've left #{trip.name}."
    else
      redirect_to trip_path(trip, anchor: "travelers"), notice: "#{membership.user.name} removed from the trip."
    end
  end
end
