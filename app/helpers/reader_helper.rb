# The reader's small view decisions (D-feed-reader), kept out of
# SectionsHelper on purpose — that file is a merge hot spot and a section
# feature has no business editing it (D37).
module ReaderHelper
  FILTER_LABELS = { "unread" => "Unread", "saved" => "Saved", "all" => "Everything" }.freeze

  # A feed's face: a monogram tile standing where a favicon would, coloured
  # from the host. Four hundred rows need to say who published each one in
  # less space than a truncated sentence, and identity is the one job a
  # 20px square does better than any amount of text.
  #
  # Nothing is fetched, ever, and that is the point rather than a shortcut.
  # A favicon service would be handed the list of every site this household
  # reads, and fetching each publisher's own icon at render time would tell
  # that publisher when their reader opened the app — the same leak
  # OUTBOUND's `noreferrer` and the stripped entry HTML exist to prevent.
  # A hash of the host gets us stable, distinguishable, offline identity for
  # nothing. (If real favicons are ever wanted, the honest way is to fetch
  # one per feed during the poll we already make and store it — never at
  # render time.)
  FACE_CLASSES = %w[
    bg-primary-700 bg-primary-800 bg-primary-900
    bg-sage-600 bg-sage-700 bg-sage-800
    bg-stone-700 bg-stone-800
  ].freeze

  # Subdomains that name the plumbing rather than the publisher. Stripping
  # them is what makes news.ycombinator.com a Y and feeds.arstechnica.com
  # an A, instead of both being filed under the machinery in front of them.
  FACE_NOISE = %w[www feeds feed rss blog news api].freeze

  def feed_face(feed, size: :sm)
    tag.span feed_monogram(feed), aria: { hidden: true },
      class: "reader-face #{FACE_CLASSES[Zlib.crc32(feed_face_key(feed)) % FACE_CLASSES.size]} " \
             "#{"reader-face-lg" if size == :lg}"
  end

  def feed_monogram(feed)
    key = feed_face_key(feed).presence || feed.display_title.to_s
    key[/[[:alnum:]]/]&.upcase || "•"
  end

  # The host with the noise labels taken off the front. Also the colour's
  # seed, so two feeds from the same publisher wear the same face.
  def feed_face_key(feed)
    labels = feed.host.to_s.split(".")
    labels.shift while labels.length > 2 && FACE_NOISE.include?(labels.first)
    labels.join(".")
  end

  # What a row calls its source. The host, because it is short, stable and
  # never truncates — "theguardian.com" rather than "World news | The G…",
  # which is the publisher's own feed title and belongs to them, not to a
  # column 45% of a phone wide. A label the user set themselves still wins:
  # they renamed it because the default wasn't what they call it.
  def reader_source(feed) = feed.label.presence || feed_face_key(feed).presence || feed.display_title

  # The section chips worth painting on a row. A label that appears on every
  # item is texture rather than information, and the catch-all lens is on
  # every item by construction (D-hobby-feeds) — so it never shows, the lens
  # you have already filtered to never shows, and at most one does.
  def reader_chips(item, current_slug: nil)
    item.feed.sections.reject { |section|
      Hobbies::OtherInterests.catch_all?(section) || section.slug == current_slug
    }.first(1)
  end

  # The day a row belongs under in the river's spine. Four hundred items
  # that all say "1h" give a list no shape; a heading per day gives it a
  # floor you can reach.
  def reader_day_label(time)
    return "Undated" if time.blank?

    case time.to_date
    when Date.current then "Earlier today"
    when Date.yesterday then "Yesterday"
    when (Date.current - 6)..Date.current then time.strftime("%A")
    else time.strftime("%B %-d")
    end
  end

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

  # What the phone's scope button says it is showing. It names the current
  # selection rather than the axis, because the control replaced two rows of
  # links whose whole job was to show you which one was bold.
  def reader_scope_label(feed, lens)
    return reader_source(feed) if feed
    return lens.name if lens

    "All feeds"
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
