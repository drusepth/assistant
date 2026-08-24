module NavigationHelper
  # `badge:` is a count that rides at the end of the row — the unread pile
  # behind a destination, which is the thing that makes anybody open it.
  # Zero doesn't draw, and the badge carries `nav-label` so it disappears
  # with the labels when the rail is collapsed rather than sitting alone
  # beside an icon.
  def nav_link_to(name, path, icon_name, badge: nil)
    active = nav_active?(path)
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    link_to path, class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}", title: name do
      parts = [ icon(icon_name, css_class: "size-4.5 shrink-0"), tag.span(name, class: "nav-label") ]
      if badge.to_i.positive?
        badge_classes = active ? "bg-primary-50/25 text-primary-50" : "bg-canvas text-soft"
        parts << tag.span(badge, class: "nav-label ml-auto rounded-full px-1.5 text-xs tabular-nums #{badge_classes}")
      end
      safe_join(parts)
    end
  end

  # One count per page render, memoized: the rail is on every page, and the
  # reader's badge is not worth a query per link.
  def reader_unread_count
    @reader_unread_count ||= FeedItem.where(feed: Current.user.feeds.active).unread.count
  end

  def section_nav_link(section)
    active = request.path == section_path(section.slug)
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    link_to section_path(section.slug), class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}", title: section.name do
      # The dot sits in a fixed-width slot so it stays put when the labels
      # go — collapsed, the column of dots is the only thing telling the
      # sections apart, and a ragged column reads as broken.
      tag.span(class: "flex w-4.5 shrink-0 justify-center") do
        tag.span("", class: "size-2 rounded-full #{section_dot_classes(section)}")
      end + tag.span(section.name, class: "nav-label")
    end
  end

  private
    def nav_active?(path)
      return request.path == path if path == root_path
      request.path == path || request.path.start_with?("#{path}/")
    end
end
