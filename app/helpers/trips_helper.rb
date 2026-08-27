module TripsHelper
  # The one bit the whole tool tracks, worn as a chip: green when it's
  # done, amber while it's still on somebody's list.
  def booking_chip(item)
    if item.booked?
      tag.span "Booked", class: "chip bg-sage-200 text-sage-900"
    else
      tag.span "Not booked", class: "chip bg-amber-100 text-amber-900"
    end
  end

  def trip_phase_chip(trip)
    case trip.phase
    when :underway then tag.span "Underway", class: "chip bg-sage-200 text-sage-900"
    when :upcoming then tag.span "Upcoming", class: "chip bg-primary-100 text-primary-800"
    else tag.span "Past", class: "chip bg-stone-100 text-stone-600"
    end
  end

  # "In 12 days" / "3 weeks away" for the hub and the index — the nomad
  # question is always "how long until we move again".
  def trip_countdown(trip, today = Date.current)
    return nil unless trip.upcoming?(today)

    days = (trip.starts_on - today).to_i
    days <= 14 ? "in #{pluralize(days, "day")}" : "in #{distance_of_time_in_words(today, trip.starts_on)}"
  end
end
