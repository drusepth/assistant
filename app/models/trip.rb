# A trip the user kept (D-travel-facet, docs/TRAVEL.md §3): a name, a date
# range and a box on the map. Everything else is derived from those three —
# the photos are the ones taken inside the box while it ran, the events are
# the ones on the calendar during it — so a trip needs no join table (Q17
# stays deferred) and stays correct as photos arrive later.
#
# Owner-only, deliberately: a trip is a lens on photo *coordinates*, which
# are owner-only under Q14. Sharing one would hand a household member the
# locations the photo pages withhold, and that question (the per-album
# "share locations" toggle) is still open.
class Trip < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, length: { maximum: 120 }
  validates :starts_on, :ends_on, presence: true
  validates :south, :west, :north, :east, presence: true
  validate :ends_on_after_starts_on

  scope :recent, -> { order(starts_on: :desc, id: :desc) }

  def self.from_candidate(candidate, name: nil)
    new(
      name: name.presence || candidate.suggested_name,
      starts_on: candidate.starts_on, ends_on: candidate.ends_on,
      place_label: candidate.place_label, cover_photo_id: candidate.cover_id,
      **candidate.bounds
    )
  end

  def days = (ends_on - starts_on).to_i + 1

  def period
    if starts_on.strftime("%b %Y") == ends_on.strftime("%b %Y")
      "#{starts_on.strftime("%-d")}–#{ends_on.strftime("%-d %b %Y")}"
    else
      "#{starts_on.strftime("%-d %b")} – #{ends_on.strftime("%-d %b %Y")}"
    end
  end

  # The trip's own photos: taken inside the box, during the range. A box
  # that crosses the antimeridian has west > east, and then "inside" means
  # outside the numeric range — the one place this arithmetic needs to know
  # the world is round.
  def photos
    user.photos.located.within(**map_bounds)
      .where(taken_at: starts_on.beginning_of_day..ends_on.end_of_day)
  end

  # Events are dates, not places, so they read through the ordinary
  # visibility path: a trip you took with your spouse can show the flight
  # they shared with you.
  def events(viewer)
    Event.visible_to(viewer)
      .where(starts_at: starts_on.beginning_of_day..ends_on.end_of_day)
      .order(:starts_at)
  end

  def cover
    return nil unless cover_photo_id

    @cover ||= user.photos.where(id: cover_photo_id).with_attached_image.first
  end

  def overlaps?(starts, ends) = starts_on <= ends && ends_on >= starts

  def map_bounds = { south: south.to_f, west: west.to_f, north: north.to_f, east: east.to_f }

  private
    def ends_on_after_starts_on
      return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

      errors.add(:ends_on, "can't be before the start")
    end
end
