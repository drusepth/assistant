# A companion on a trip (D-trip-companions): another household member who
# was — or will be — along for it. Membership is the trip's sharing
# mechanism, deliberately not an AccessGrant: a shared trip is a place the
# household collaborates (itinerary, comments, posted photos), not a
# read-only window onto the owner's data. What membership never shares is
# anything derived from photo coordinates — the map and the camera roll
# stay owner-only under Q14.
class TripMembership < ApplicationRecord
  belongs_to :trip
  belongs_to :user

  validates :user_id, uniqueness: { scope: :trip_id, message: "is already on this trip" }
  validate :user_in_owners_household
  validate :user_is_not_the_owner

  private
    def user_in_owners_household
      return if trip.blank? || user.blank?
      return if user.household_id == trip.user.household_id

      errors.add(:user, "must be in the same household")
    end

    def user_is_not_the_owner
      return if trip.blank? || user.blank? || user_id != trip.user_id

      errors.add(:user, "already owns this trip")
    end
end
