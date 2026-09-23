# How the app shows a measurement to one person. Pounds and miles are the
# norm — they are what the columns hold (`pets.weight_lb`,
# `places.radius_mi`, `happenings.distance_mi`) and what nearly everyone
# reads — and kilograms and kilometres are the exception, a display
# conversion for the user who picks them in Settings (D-measurement-units).
#
# This is the one place a stored number meets a metric reader, both ways —
# the figure a page prints and the figure a form posts — so no view carries
# a conversion factor of its own. For an imperial reader every method here
# is the identity plus formatting.
class Units < Data.define(:system)
  SYSTEMS = %w[ imperial metric ].freeze
  LABELS = { "imperial" => "Pounds and miles", "metric" => "Kilograms and kilometres" }.freeze

  LB_PER_KG = BigDecimal("2.20462262185")
  KM_PER_MI = BigDecimal("1.609344")

  def self.for(system) = new(system: SYSTEMS.include?(system.to_s) ? system.to_s : SYSTEMS.first)

  def metric? = system == "metric"
  def label = LABELS.fetch(system)

  # --- Weight (stored in lb) ---

  def weight_unit = metric? ? "kg" : "lb"
  def weight_step = metric? ? "0.01" : "0.1"

  # A stored pound figure in the reader's unit; nil stays nil.
  def weight(lb)
    return nil if lb.nil?

    metric? ? (lb.to_d / LB_PER_KG).round(2) : lb.to_d.round(2)
  end

  # What a form posted, back to pounds for the column; blank is nil.
  def lb_from(value)
    return nil if value.blank?

    metric? ? (value.to_d * LB_PER_KG).round(2) : value.to_d
  end

  def weight_phrase(lb) = lb.nil? ? nil : "#{plain(weight(lb))} #{weight_unit}"

  # --- Distance (stored in mi) ---

  def distance_unit = metric? ? "km" : "mi"

  def distance(mi)
    return nil if mi.nil?

    metric? ? mi.to_d * KM_PER_MI : mi.to_d
  end

  # A whole number of the reader's unit back to whole miles. A metric radius
  # snaps to the nearest mile — the column's grain — which is close enough
  # for "counts as here".
  def mi_from(value)
    return nil if value.blank?

    (metric? ? value.to_d / KM_PER_MI : value.to_d).round
  end

  # A mile range (a validation's bounds) as the whole numbers of the
  # reader's unit that land inside it, for a form's min and max.
  def distance_range(mi_range)
    distance(mi_range.min).ceil..distance(mi_range.max).floor
  end

  def distance_phrase(mi)
    return nil if mi.nil?

    figure = distance(mi)
    figure < 1 ? "under 1 #{distance_unit}" : "#{figure.round} #{distance_unit}"
  end

  private
    # 31.2, not 31.20; 50, not 50.0.
    def plain(number)
      number == number.to_i ? number.to_i.to_s : number.to_d.round(2).to_s("F")
    end
end
