# How the app shows a measurement to one person — pounds and miles, or
# kilograms and kilometres — from the setting they chose in Settings.
#
# Storage never changes: a pet's weight is kept in kg and a place's radius in
# km, because those columns are also read by the model (a vet-sheet landing,
# a pet tool's context), by the radar's distance maths, and by providers that
# take kilometres. This is the one place a stored number meets the reader's
# system, both ways — the figure a page prints and the figure a form posts —
# so no view carries a conversion factor of its own.
#
# The precisions are chosen so a round trip is stable: a stored weight is
# 0.01 kg (finer than the 0.1 lb a form shows), and a radius is a whole
# kilometre (finer than the whole mile a form shows), so saving a form
# untouched never nudges the number.
class Units < Data.define(:system)
  SYSTEMS = %w[ imperial metric ].freeze
  LABELS = { "imperial" => "Pounds and miles", "metric" => "Kilograms and kilometres" }.freeze

  LB_PER_KG = BigDecimal("2.20462262185")
  KM_PER_MI = BigDecimal("1.609344")

  def self.for(system) = new(system: SYSTEMS.include?(system.to_s) ? system.to_s : SYSTEMS.first)

  def metric? = system == "metric"
  def label = LABELS.fetch(system)

  # --- Weight (stored in kg) ---

  def weight_unit = metric? ? "kg" : "lb"
  def weight_step = metric? ? "0.01" : "0.1"

  # A stored kg figure in the reader's unit; nil stays nil.
  def weight(kg)
    return nil if kg.nil?

    metric? ? kg.to_d.round(2) : (kg.to_d * LB_PER_KG).round(1)
  end

  # What a form posted, back to kg for the column; blank is nil.
  def kg_from(value)
    return nil if value.blank?

    metric? ? value.to_d : (value.to_d / LB_PER_KG).round(2)
  end

  def weight_phrase(kg) = kg.nil? ? nil : "#{plain(weight(kg))} #{weight_unit}"

  # --- Distance (stored in km) ---

  def distance_unit = metric? ? "km" : "mi"

  def distance(km)
    return nil if km.nil?

    metric? ? km.to_d : km.to_d / KM_PER_MI
  end

  # A whole number of the reader's unit back to whole kilometres.
  def km_from(value)
    return nil if value.blank?

    (metric? ? value.to_d : value.to_d * KM_PER_MI).round
  end

  # A kilometre range (a validation's bounds) as the whole numbers of the
  # reader's unit that land inside it, for a form's min and max.
  def distance_range(km_range)
    distance(km_range.min).ceil..distance(km_range.max).floor
  end

  def distance_phrase(km)
    return nil if km.nil?

    figure = distance(km)
    figure < 1 ? "under 1 #{distance_unit}" : "#{figure.round} #{distance_unit}"
  end

  private
    # 31.2, not 31.20; 50, not 50.0.
    def plain(number)
      number == number.to_i ? number.to_i.to_s : number.to_s("F")
    end
end
