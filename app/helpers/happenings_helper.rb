# The event radar's row copy (D-event-radar), kept out of SectionsHelper on
# purpose (D37).
module HappeningsHelper
  # The day heading in the river: near days by name, the rest by date.
  def happening_day_label(date)
    case date
    when Date.current then "Today"
    when Date.tomorrow then "Tomorrow"
    when (Date.current + 2)..(Date.current + 6) then date.strftime("%A")
    else date.strftime("%a, %-d %b")
    end
  end

  # "7:30 pm", "All day", "Open since 3 Oct" — the row's first column.
  def happening_when(happening)
    return "Open since #{happening.created_at.strftime("%-d %b")}" if happening.kind_opening?
    return "All day" if happening.all_day?

    happening.starts_at.strftime("%-l:%M %P").sub(":00", "")
  end

  # The short date-first title a nudge or a card wears: "Sat 3 Oct · Bird walk".
  def happening_short(happening)
    return happening.title if happening.kind_opening?

    "#{happening.starts_at.strftime("%a %-d %b")} · #{happening.title}"
  end

  def happening_distance(happening)
    return nil if happening.distance_km.blank?

    km = happening.distance_km.to_f
    km < 1 ? "under 1 km" : "#{km.round} km"
  end

  # Venue and distance on one line, only what is known.
  def happening_where(happening)
    [ happening.location.presence, happening_distance(happening) ].compact.join(" · ").presence
  end

  # Where to go looking for a calendar the app can read (D-listing-feeds
  # §4.5): a search in the *user's* browser, so the app sends nothing.
  def find_calendar_link(place, what, label = "Find it")
    query = "#{place.name} #{what}"
    link_to label, "https://duckduckgo.com/?q=#{ERB::Util.url_encode(query)}",
      class: "reader-filter", **ReaderHelper::OUTBOUND
  end
end
