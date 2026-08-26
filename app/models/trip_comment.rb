# A note on the trip's own page (D-trip-companions), visible to everyone
# travelling on it: "the host says parking is around back", "let's do the
# hot springs the first weekend". The first commentable thing in the app —
# a trip is the first place two people genuinely share, rather than one
# person granting the other a view.
class TripComment < ApplicationRecord
  belongs_to :trip
  belongs_to :user

  validates :body, presence: true, length: { maximum: 4_000 }

  scope :chronological, -> { order(:created_at, :id) }

  def editable_by?(viewer) = viewer.id == user_id || viewer.id == trip.user_id
end
