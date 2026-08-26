# The allergies card's severity chips (docs/HEALTH.md §8). Its own helper
# rather than another entry in SectionsHelper: section features own their
# files (D37), and that one is the merge hot spot the rule exists for.
module AllergiesHelper
  SEVERITY_CHIPS = {
    "severe" => [ "Severe", "bg-red-100 text-red-800" ],
    "moderate" => [ "Moderate", "bg-primary-200 text-primary-800" ],
    "mild" => [ "Mild", "bg-stone-200 text-stone-700" ]
  }.freeze

  def allergy_severity_label(severity) = SEVERITY_CHIPS.dig(severity, 0)
  def allergy_severity_chip_classes(severity) = SEVERITY_CHIPS.dig(severity, 1)

  # Options for the add form's select, worst first, with the blank default
  # spelled out — "how bad" is a question the user is allowed not to answer,
  # and a guessed severity is worse than a missing one.
  def allergy_severity_options
    Note::SEVERITIES.map { |severity| [ allergy_severity_label(severity), severity ] }
  end
end
