# Shared authorization for the trip page and everything nested under it
# (D-trip-companions). Two levels, matching the two roles a trip has:
# travellers (the owner plus companions) collaborate — itinerary, comments,
# posted photos — while the owner alone edits the trip itself, manages who
# is on it, and removes it. Both raise RecordNotFound rather than deny, so
# a trip you aren't on doesn't exist as far as you can tell.
module TripAccess
  extend ActiveSupport::Concern

  private
    def find_trip_as_traveler(id) = Trip.involving(Current.user).find(id)

    def find_trip_as_owner(id) = Current.user.trips.find(id)
end
