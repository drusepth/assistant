module NavigationHelper
  # `count:` is a number that rides at the end of the row — the unread pile
  # behind a destination, which is the thing that makes anybody open it.
  # Zero doesn't draw, and the count carries `nav-label` so it disappears
  # with the labels when the rail is collapsed rather than sitting alone
  # beside an icon.
  def nav_link_to(name, path, icon_name, count: nil)
    active = nav_active?(path)
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    link_to path, class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}",
      aria: { label: name }, data: tooltip_data(name, nav_signals.row(name)) do
      safe_join([
        icon(icon_name, css_class: "size-4.5 shrink-0"),
        tag.span(name, class: "nav-label"),
        nav_count(count, active)
      ].compact)
    end
  end

  # The pile behind a row, drawn the same way wherever it rides. Zero doesn't
  # draw, and it carries `nav-label` so it disappears with the labels when
  # the rail is collapsed rather than sitting alone beside an icon.
  def nav_count(count, active)
    return nil unless count.to_i.positive?

    classes = active ? "bg-primary-50/25 text-primary-50" : "bg-canvas text-soft"
    tag.span(count, class: "nav-label ml-auto rounded-full px-1.5 text-xs tabular-nums #{classes}")
  end

  # One count per page render, memoized: the rail is on every page, and the
  # reader's unread pile is not worth a query per link. It rides the Hobbies
  # row rather than a Reader row of its own (D-hobby-feeds) — the river is
  # what makes that section different every day, not a destination beside it.
  def reader_unread_count
    @reader_unread_count ||= FeedItem.where(feed: Current.user.feeds.active).unread.count
  end

  def section_nav_link(section)
    active = request.path == section_path(section.slug) || nav_section_slug == section.slug
    count = reader_unread_count if section.slug == "hobbies"
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    # "Budget" reads ambiguously the moment it's off its own page, and a
    # collapsed rail is nothing but dots — so the name the tooltip and the
    # screen reader get is the qualified one. `top_level?` reads the foreign
    # key rather than the association, so the common row costs no query to
    # learn it has no parent to name.
    label = section.top_level? ? section.name : section.qualified_name

    link_to section_path(section.slug), class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}",
      aria: { label: label }, data: tooltip_data(label, nav_signals.section(section)) do
      # The dot sits in a fixed-width slot so it stays put when the labels
      # go — collapsed, the column of dots is the only thing telling the
      # sections apart, and a ragged column reads as broken.
      tag.span(class: "flex w-4.5 shrink-0 justify-center") do
        tag.span("", class: "size-2 rounded-full #{section_dot_classes(section)}")
      end + tag.span(section.name, class: "nav-label") + nav_count(count, active).to_s
    end
  end

  # The top-level section a page belongs to without being that section's own
  # page, so the rail keeps your place one level down: a subsection or lens
  # page lights its root (Budget lights Money, a pet's lens lights Pets), and a
  # page outside SectionsController claims one with
  # `content_for :nav_section, "pets"`.
  def nav_section_slug
    content_for(:nav_section).presence ||
      (section_root_slug(@section) if controller_name == "sections" && @section)
  end

  # One signals object per render, so the rail's dozen rows cost a handful of
  # batched aggregates rather than a query each.
  def nav_signals
    @nav_signals ||= Navigation::Signals.new(Current.user)
  end

  # The lenses the rail draws. It comes from the signals object because that
  # object needs the same list to batch over — asking the user twice is two
  # trips for one answer.
  def nav_sections = nav_signals.sections

  private
    # A nav tooltip carries the row's name (the only label there is when the
    # rail is collapsed) and, when there is one, what's waiting behind it.
    # It never carries a description: restating the label to somebody who is
    # already pointing at it is what made these tooltips worth nothing.
    def tooltip_data(title, signal)
      data = { controller: "tooltip", tooltip_title_value: title }
      data[:tooltip_detail_value] = signal.body if signal&.body.present?
      data[:tooltip_badge_value] = signal.badge if signal&.badge.present?
      data
    end

    def nav_active?(path)
      return request.path == path if path == root_path
      request.path == path || request.path.start_with?("#{path}/")
    end
end
