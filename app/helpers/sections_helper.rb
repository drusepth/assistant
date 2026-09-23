# Stable identity colors per top-level section; subsections inherit their
# parent's color. Literal class strings so Tailwind's scanner sees them.
#
# The seven colors are drawn from the two Organic ramps rather than from
# Tailwind's stock hues: the palette is warm on purpose, and a stock rose
# or sky next to cream reads as a foreign object. Each area takes a
# distinct step so they stay tellable apart at dot size, alternating
# terracotta and sage so neighbours in the sidebar never collide.
module SectionsHelper
  CHIP_CLASSES = {
    "health" => "bg-primary-200 text-primary-900",
    "hobbies" => "bg-primary-100 text-primary-800",
    "education" => "bg-sage-100 text-sage-800",
    "career" => "bg-sage-200 text-sage-900",
    "people" => "bg-primary-100 text-primary-700",
    "money" => "bg-sage-100 text-sage-700",
    "rights" => "bg-primary-200 text-primary-800",
    "travel" => "bg-sage-300 text-sage-900",
    "pets" => "bg-primary-300 text-primary-900"
  }.freeze

  DOT_CLASSES = {
    "health" => "bg-primary-800",
    "hobbies" => "bg-primary-500",
    "education" => "bg-sage-500",
    "career" => "bg-sage-700",
    "people" => "bg-primary-400",
    "money" => "bg-sage-400",
    "rights" => "bg-primary-700",
    "travel" => "bg-sage-600",
    "pets" => "bg-primary-600"
  }.freeze

  def section_chip_classes(section)
    CHIP_CLASSES.fetch(section_root_slug(section), "bg-stone-100 text-stone-700")
  end

  def section_dot_classes(section)
    DOT_CLASSES.fetch(section_root_slug(section), "bg-stone-400")
  end

  def section_root_slug(section)
    (section.parent || section).slug
  end

  # The care radar's four states (docs/HEALTH.md), as chip copy + classes.
  CARE_STATE_CHIPS = {
    booked: [ "Booked", "bg-sage-200 text-sage-800" ],
    ok: [ "On track", "bg-sage-100 text-sage-700" ],
    due: [ "Due", "bg-primary-200 text-primary-800" ],
    unknown: [ "Not tracked", "bg-stone-200 text-stone-700" ]
  }.freeze

  def care_state_label(state) = CARE_STATE_CHIPS.fetch(state).first
  def care_state_chip_classes(state) = CARE_STATE_CHIPS.fetch(state).second

  def care_status_line(status)
    case status.state
    when :booked
      "#{status.next_visit.title} — #{status.next_visit_on.strftime("%b %-d, %Y")}, " \
        "#{distance_of_time_in_words(Date.current, status.next_visit_on)} away."
    when :ok
      "Last #{status.kind.visit_noun} #{care_date(status.last_visit_on, status.kind)} — " \
        "nothing needed until around #{care_date(status.due_on, status.kind)}."
    when :due
      "Last #{status.kind.visit_noun} #{care_date(status.last_visit_on, status.kind)} — due since #{care_date(status.due_on, status.kind)}."
    else
      "No #{status.kind.visit_noun.pluralize} on record yet. Log the last one and the radar takes it from there."
    end
  end

  # A yearly rhythm reads in months; a monthly or six-weekly one (a pet's
  # parasite treatment, a groom — D-pet-care-radar) needs the day, or the
  # month is half over before the line says anything.
  def care_date(date, kind = nil)
    kind&.short_cadence? ? date.strftime("%b %-d") : date.strftime("%b %Y")
  end


  # The "Counts as" select on a health event (docs/HEALTH.md §3): the
  # user's word beats the keywords. Auto shows what classification would
  # say, so choosing it is informed.
  def care_kind_options(event)
    radar = Health::CareRadar.new(Current.user)
    auto = radar.classify(event.title)
    options = [ [ "Auto — #{auto ? auto.label : "not routine care"}", "" ] ]
    options += radar.kinds.map { |kind| [ kind.label, kind.key ] }
    options << [ "Not routine care", Health::CareRadar::EXCLUDED ]
    options_for_select(options, event.care_kind)
  end

  # One line of engagement signal for a subsection tile: the next planned
  # event beats counts beats an honest "Nothing yet".
  def section_summary_signal(summary)
    if summary.next_event
      "#{summary.next_event.title} · #{summary.next_event.starts_at.strftime("%b %-d")}"
    elsif !summary.quiet?
      in_flight = []
      in_flight << pluralize(summary.open_tasks_count, "open task") if summary.open_tasks_count.positive?
      in_flight << pluralize(summary.active_goals_count, "project") if summary.active_goals_count.positive?
      in_flight.join(" · ")
    else
      "Nothing yet"
    end
  end
end
