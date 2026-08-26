# How you get there and back (D-trip-spine): a flight, a drive, a train —
# or a car rental, which is a leg with a return date rather than a route.
# Like a stay, a leg's whole job is to answer "is this booked yet?" while
# the trip is still ahead of you.
class TripLeg < ApplicationRecord
  belongs_to :trip

  enum :kind, {
    flight: "flight", drive: "drive", train: "train", bus: "bus",
    ferry: "ferry", car_rental: "car_rental", other: "other"
  }, prefix: :kind

  enum :booking_status, { planned: "planned", booked: "booked" }

  validates :starts_on, presence: true
  validates :origin, :destination, :carrier, length: { maximum: 120 }
  validate :ends_on_after_starts_on

  scope :by_date, -> { order(:starts_on, :id) }

  KIND_LABELS = {
    "flight" => "Flight", "drive" => "Drive", "train" => "Train", "bus" => "Bus",
    "ferry" => "Ferry", "car_rental" => "Car rental", "other" => "Travel"
  }.freeze

  # Your own car needs no booking; a drive defaults to one so the hub never
  # nags about it, and flipping it to planned turns the tracking back on for
  # the year you start renting.
  BOOKLESS_KINDS = %w[ drive ].freeze

  def kind_label = KIND_LABELS.fetch(kind)

  def display_name
    if origin.present? && destination.present?
      "#{kind_label} · #{origin} → #{destination}"
    elsif destination.present?
      "#{kind_label} to #{destination}"
    elsif carrier.present?
      "#{kind_label} · #{carrier}"
    else
      kind_label
    end
  end

  def period
    return starts_on.strftime("%-d %b") if ends_on.blank? || ends_on == starts_on

    "#{starts_on.strftime("%-d %b")} – #{ends_on.strftime("%-d %b")}"
  end

  def departure_time = departs_at&.strftime("%-l:%M %p")&.strip

  private
    def ends_on_after_starts_on
      return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

      errors.add(:ends_on, "can't be before the start")
    end
end
