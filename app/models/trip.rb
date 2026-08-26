# A trip (D-travel-facet, D-trip-spine; docs/TRAVEL.md, docs/TRIPS_PLAN.md).
# Two births, one record:
#
# - **Found in photos**: the detector's candidate — a name, a date range and
#   a box on the map. Its photos are derived (taken inside the box while it
#   ran) so they join the trip on their own as they arrive.
# - **Planned ahead**: a name, a place and dates typed before going. No box
#   yet, so no derived photos — the itinerary (stays and legs) is what the
#   page is for until you're back.
#
# The box, when present, is only ever computed server-side from the owner's
# own photos; bounds are all-or-none and never taken from a form.
#
# Sharing is membership (D-trip-companions), not an AccessGrant: companions
# collaborate on the itinerary, comment, and post photos. What they never
# see is anything derived from photo *coordinates* — the map and the camera
# roll stay owner-only under Q14, and each traveller posts photos to the
# trip explicitly instead.
class Trip < ApplicationRecord
  belongs_to :user

  has_many :stays, dependent: :destroy, inverse_of: :trip
  has_many :legs, class_name: "TripLeg", dependent: :destroy, inverse_of: :trip
  has_many :memberships, class_name: "TripMembership", dependent: :destroy
  has_many :companions, through: :memberships, source: :user
  has_many :comments, class_name: "TripComment", dependent: :destroy
  has_many :trip_photos, dependent: :destroy
  has_many :posted_photos, through: :trip_photos, source: :photo

  validates :name, presence: true, length: { maximum: 120 }
  validates :place_label, length: { maximum: 120 }
  validates :starts_on, :ends_on, presence: true
  validate :ends_on_after_starts_on
  validate :bounds_all_or_none

  scope :recent, -> { order(starts_on: :desc, id: :desc) }
  # Trips this user travels on: their own, plus the household trips they
  # were added to. The write-side equivalent of visible_to, scoped to the
  # one kind of sharing trips have.
  scope :involving, ->(viewer) {
    where(user: viewer)
      .or(where(id: TripMembership.where(user: viewer).select(:trip_id)))
  }

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

  # Upcoming, underway, or past — never stored, so it can't go stale.
  def phase(today = Date.current)
    return :upcoming if starts_on > today
    return :past if ends_on < today

    :underway
  end

  def upcoming?(today = Date.current) = phase(today) == :upcoming
  def underway?(today = Date.current) = phase(today) == :underway
  def past?(today = Date.current) = phase(today) == :past

  # Whether the trip has its box on the map — every photo-derived feature
  # keys off this, so a planned trip is simply a trip without them yet.
  def placed? = south.present? && west.present? && north.present? && east.present?

  def travelers = [ user ] + companions.order(:name)

  def traveler?(viewer) = viewer.id == user_id || memberships.exists?(user_id: viewer.id)

  # The itinerary: stays and legs in one chronological run. Legs sort ahead
  # of stays on a shared date — you fly in before you check in.
  def timeline
    (legs.by_date.to_a + stays.by_date.to_a).sort_by do |item|
      date = item.is_a?(Stay) ? item.check_in : item.starts_on
      [ date, item.is_a?(Stay) ? 1 : 0, item.id ]
    end
  end

  # Nights inside the trip's dates with nowhere yet to sleep, as date
  # ranges (each range's end is the night before the next check-in — the
  # half-open convention from Stay#covers?). An empty itinerary returns the
  # whole trip; the view words that case differently.
  def lodging_gaps
    nights = (starts_on...ends_on).reject { |night| stays.any? { |stay| stay.covers?(night) } }
    nights.slice_when { |night, following| following != night + 1 }.map { |run| run.first..run.last }
  end

  # What the itinerary costs (D-trip-costs), split by the same bit
  # everything else tracks: booked is committed money, planned is money
  # still waiting on somebody to click "book".
  def booked_cost_cents = itinerary_cost_cents(:booked?)
  def planned_cost_cents = itinerary_cost_cents(:planned?)

  # Ruby filters, not scopes, so a page that preloaded stays and legs pays
  # no extra queries. A drive in your own car never counts as unbooked.
  def unbooked_stays = stays.select(&:planned?)

  def unbooked_legs
    legs.select { |leg| leg.planned? && !TripLeg::BOOKLESS_KINDS.include?(leg.kind) }
  end

  # The trip's own derived photos: taken inside the box, during the range.
  # A box that crosses the antimeridian has west > east, and then "inside"
  # means outside the numeric range — the one place this arithmetic needs
  # to know the world is round. No box yet, no derived photos.
  def photos
    return user.photos.none unless placed?

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
    def itinerary_cost_cents(predicate)
      (stays.to_a + legs.to_a).select(&predicate).sum { |item| item.cost_cents.to_i }
    end

    def ends_on_after_starts_on
      return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

      errors.add(:ends_on, "can't be before the start")
    end

    def bounds_all_or_none
      bounds = [ south, west, north, east ]
      return if bounds.all?(&:present?) || bounds.all?(&:blank?)

      errors.add(:base, "The map box needs all four edges")
    end
end
