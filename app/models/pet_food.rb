# What a pet is eating, and since when (D-pet-food-shelf). D36 made a
# medication a Note with a kind, because a med list is prose nobody does
# arithmetic on. Food is the opposite case and earns columns: two numbers are
# *derived* rather than guessed — when the bag runs out, and what it costs a
# month — and both feed surfaces that already exist (the calendar, the
# budget).
#
# Superseding a food ends its row rather than editing it, which is what keeps
# a diet history: "what is she eating, and since when?" is the first question
# at every vet visit and the whole content of an elimination trial.
#
# What it deliberately does not do: portions from breed and weight, calories,
# or any judgment of a food's quality. Those are a vet's numbers. The bag
# states a feeding amount and this holds *the bag's* number.
class PetFood < ApplicationRecord
  FORMS = %w[ dry wet raw prescription treats supplement ].freeze
  FORM_LABELS = {
    "dry" => "Dry", "wet" => "Wet", "raw" => "Raw", "prescription" => "Prescription",
    "treats" => "Treats", "supplement" => "Supplement"
  }.freeze

  # Weight units convert; "cans" and "scoops" don't, so a bag measured in cans
  # is fed in cans or the arithmetic is refused rather than guessed.
  UNITS = %w[ g kg oz lb cans scoops cups ].freeze
  GRAMS = { "g" => 1.0, "kg" => 1000.0, "oz" => 28.3495, "lb" => 453.592 }.freeze

  belongs_to :pet

  validates :name, presence: true
  validates :form, inclusion: { in: FORMS }
  validates :unit, inclusion: { in: UNITS }
  validates :started_on, presence: true
  validates :amount_per_day, :package_amount,
    numericality: { greater_than: 0 }, allow_nil: true
  validates :package_cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :current, -> { where(ended_on: nil).order(:form, :name) }
  scope :past, -> { where.not(ended_on: nil).order(ended_on: :desc) }

  def current? = ended_on.nil?
  def form_label = FORM_LABELS.fetch(form, form.humanize)
  def display_name = [ brand.presence, name ].compact.join(" ")

  # How long one package lasts, or nil when the numbers can't say — a bag in
  # kilos fed in scoops is two different measurements, and converting them
  # would be inventing a density.
  def days_per_package
    return nil if amount_per_day.blank? || package_amount.blank?

    daily = in_grams(amount_per_day)
    package = in_grams(package_amount)
    return nil if daily.nil? || package.nil? || daily.zero?

    (package / daily).floor
  end

  # When to reorder, counted from when this bag was opened. No opened_on means
  # no claim: the app would rather say nothing than count from a date that
  # drifts a bag further out every month.
  def runs_out_on
    days = days_per_package
    return nil if days.nil? || opened_on.nil?

    opened_on + days
  end

  # A month of this food, in cents. 30.44 days, because a bag lasting 34 days
  # is not "one bag a month" and rounding it to one is where budget numbers
  # start lying.
  def monthly_cost_cents
    days = days_per_package
    return nil if days.nil? || days.zero? || package_cost_cents.blank?

    (package_cost_cents * (30.44 / days)).round
  end

  private
    # Weight units share a scale; counted units don't convert to anything.
    def in_grams(amount)
      factor = GRAMS[unit]
      factor && (amount.to_f * factor)
    end
end
