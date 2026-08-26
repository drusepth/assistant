# A photo posted to a trip's page (D-trip-companions) for everyone on the
# trip to see. Posting is the explicit act that shares the photo — the
# derived camera roll never leaves its owner — and viewers reach it through
# the ordinary variant path, so what they receive is EXIF-stripped like any
# other shared photo. `user` is the poster, and must own the photo: nobody
# can post someone else's picture onto a trip.
class TripPhoto < ApplicationRecord
  belongs_to :trip
  belongs_to :photo
  belongs_to :user

  validates :photo_id, uniqueness: { scope: :trip_id, message: "is already on this trip" }
  validate :poster_owns_photo

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  private
    def poster_owns_photo
      return if photo.blank? || user.blank? || photo.user_id == user_id

      errors.add(:photo, "must be your own")
    end
end
