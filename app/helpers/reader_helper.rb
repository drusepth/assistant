# The reader's small view decisions (D-feed-reader), kept out of
# SectionsHelper on purpose — that file is a merge hot spot and a section
# feature has no business editing it (D37).
module ReaderHelper
  FILTER_LABELS = { "unread" => "Unread", "saved" => "Saved", "all" => "Everything" }.freeze

  # A filter is a small text link with the current one in ink, not a pill:
  # at the density this page runs at, a row of pills outweighs the list it
  # filters. Keeps the rest of the river's state — switching the filter
  # shouldn't silently drop the hobby you were reading.
  def reader_filter_link(label, params_override, active:)
    link_to label, reader_path(request.query_parameters.except("offset").merge(params_override)),
      class: "reader-filter #{"reader-filter-on" if active}"
  end

  # The separator between filter links. A dot, because a pipe reads as a
  # table border and a gap alone doesn't group.
  def reader_dot
    tag.span("·", class: "text-xs text-stone-400", aria: { hidden: true })
  end

  # "12m", "3h", "2d", then the date. A river is scanned in a column two
  # characters wide, so anything longer than that is furniture — the full
  # timestamp is on the element's title.
  def reader_age(time)
    return nil if time.blank?

    seconds = Time.current - time
    case seconds
    when ..0 then "now"
    when ...1.hour then "#{(seconds / 60).floor}m"
    when ...1.day then "#{(seconds / 3600).floor}h"
    when ...7.days then "#{(seconds / 86_400).floor}d"
    else time.strftime("%b %-d")
    end
  end

  # "12 unread", "3 saved", "40 items" — the count says which pile it is
  # counting, because the filter row above it is small on purpose.
  def reader_count_label(total, filter)
    case filter
    when "unread" then "#{total} unread"
    when "saved" then "#{total} saved"
    else pluralize(total, "item")
    end
  end

  # A feed nothing has claimed: it sits in the catch-all, or (briefly, while
  # a classify job is in flight) nowhere at all. The feed list uses this to
  # decide which rows get a filing picker and a Re-file verb — the two
  # affordances that do nothing for a feed already filed under a hobby.
  def feed_unfiled?(feed)
    feed.sections.empty? || feed.sections.all? { |section| Hobbies::OtherInterests.catch_all?(section) }
  end

  # An item's link goes to a stranger's site: new tab, no window handle back
  # into the app, and no referrer telling them which of our pages sent you.
  OUTBOUND = { target: "_blank", rel: "noopener noreferrer nofollow" }.freeze

  # Only http(s) reaches an href. Feeds are hostile input, and a
  # `javascript:` link in an entry would otherwise be one click from
  # running inside a signed-in session.
  def reader_safe_url(url)
    url.to_s.match?(%r{\Ahttps?://\S+\z}i) ? url.to_s : nil
  end
end
