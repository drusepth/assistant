# Where you'll sleep, and for which nights (D-trip-spine): an Airbnb, a
# hotel, a friend's spare room. A stay belongs to its trip — collaborators
# on the trip can all see and edit it — and carries the one bit the whole
# feature turns on: whether it is actually booked or still just planned.
#
# Nights are half-open: a stay covers check-in up to but not including
# check-out, so back-to-back stays (check out of Austin the morning you
# check into Denver) leave no phantom gap between them.
class Stay < ApplicationRecord
  include HasCost

  belongs_to :trip

  enum :kind, {
    airbnb: "airbnb", hotel: "hotel", vacation_rental: "vacation_rental",
    friends_family: "friends_family", camping: "camping", other: "other"
  }, prefix: :kind

  enum :booking_status, { planned: "planned", booked: "booked" }

  validates :location, presence: true, length: { maximum: 120 }
  validates :name, length: { maximum: 160 }
  validates :check_in, :check_out, presence: true
  validate :check_out_after_check_in

  scope :by_date, -> { order(:check_in, :id) }

  # Coordinates come from the typed location matched against the local
  # gazetteer (D-stay-pins) — never from photos, never from the network —
  # so the itinerary map is ordinary shared trip data, not a Q14 surface.
  # A location the gazetteer has never heard of pins nothing, which is the
  # honest answer.
  before_save :locate_from_gazetteer, if: :will_save_change_to_location?

  KIND_LABELS = {
    "airbnb" => "Airbnb", "hotel" => "Hotel", "vacation_rental" => "Vacation rental",
    "friends_family" => "Friends & family", "camping" => "Camping", "other" => "Stay"
  }.freeze

  def kind_label = KIND_LABELS.fetch(kind)

  def nights = (check_out - check_in).to_i

  # The half-open test the gap math and the "where are you today" question
  # both use. Check-out day belongs to wherever you sleep *that* night.
  def covers?(day) = day >= check_in && day < check_out

  def display_name = name.presence || "#{kind_label} in #{location}"

  def period
    if check_in.strftime("%b %Y") == check_out.strftime("%b %Y")
      "#{check_in.strftime("%-d")}–#{check_out.strftime("%-d %b")}"
    else
      "#{check_in.strftime("%-d %b")} – #{check_out.strftime("%-d %b")}"
    end
  end

  def located? = latitude.present? && longitude.present?

  private
    def locate_from_gazetteer
      match = Datasets::Places.current.named(location)
      self.latitude = match&.latitude
      self.longitude = match&.longitude
    end

    def check_out_after_check_in
      return if check_in.blank? || check_out.blank? || check_out > check_in

      errors.add(:check_out, "must be after check-in")
    end
end
