# Somewhere the user cares about what happens near (D-place-subscriptions):
# home, the town they drive to on weekends, where the grandparents live. A
# place is the unit of subscription for the event radar — the listing
# sources hang off it, and its two knobs decide what counts as "here"
# (radius) and how far ahead the watcher may interrupt (lead time).
#
# Named from the gazetteer the app ships and never geocoded: typing "Tulsa"
# resolves through `Datasets::Places.named`, the same call a trip's stay
# makes (D-stay-pins), and a name the file doesn't know is refused rather
# than sent anywhere. Per user and never shared — a declared interest in a
# location is exactly what D9 keeps private and Q14 keeps from crossing
# users.
class Place < ApplicationRecord
  belongs_to :user
  has_many :listing_sources, -> { order(:created_at) }, dependent: :destroy, inverse_of: :place
  has_many :happenings, through: :listing_sources

  DEFAULT_RADIUS_MI = 25
  DEFAULT_LEAD_DAYS = 14
  RADIUS_RANGE = 3..190
  LEAD_RANGE = 1..60

  validates :name, presence: true, length: { maximum: 120 }
  validates :radius_mi, numericality: { only_integer: true, in: RADIUS_RANGE }
  validates :lead_days, numericality: { only_integer: true, in: LEAD_RANGE }
  validate :names_a_known_town

  normalizes :name, with: ->(value) { value.to_s.squish }

  before_validation :locate_from_gazetteer, if: :will_save_change_to_name?

  scope :alerting, -> { where(alerts: true) }

  def located? = latitude.present? && longitude.present?

  def qualified_name = country.present? ? "#{name}, #{country}" : name

  # How far a coordinate is from this place, in miles (D-measurement-units)
  # — the haversine the gazetteer already has, so "near" is one arithmetic
  # everywhere.
  def distance_to(lat, lng)
    Datasets::Places.distance_km(latitude.to_f, longitude.to_f, lat.to_f, lng.to_f) / Units::KM_PER_MI.to_f
  end

  def within?(lat, lng) = distance_to(lat, lng) <= radius_mi

  # The window the watcher may nudge inside: today through the lead time.
  def lead_window(today = Date.current) = today..(today + lead_days)

  # Somebody looked at what's on here. Denormalized so the sweep can back
  # off sources nobody opens without a query per source.
  def touch_opened!(at = Time.current)
    update_column(:last_opened_at, at) if last_opened_at.nil? || last_opened_at < at - 1.hour
  end

  private
    def locate_from_gazetteer
      match = Datasets::Places.current.named(name)
      self.latitude = match&.latitude
      self.longitude = match&.longitude
      self.country = match&.country
      self.name = match.name if match
    end

    # The honest refusal: the file holds settlements, and a place it can't
    # name is a place whose "near" would be a guess.
    def names_a_known_town
      return if located?

      errors.add(:name, "isn't a town the map knows — try the nearest city, or add a country (“Paris, France”)")
    end
end
