module NavigationHelper
  NAV_METADATA = {
    "Dashboard" => { subtitle: "Overview & daily summary", shortcut: "⌘1" },
    "Today" => { subtitle: "Current agenda", badge: "Today", shortcut: "⌘2" },
    "Calendar" => { subtitle: "Schedule & events", shortcut: "⌘3" },
    "Tasks" => { subtitle: "To-do items & priorities", shortcut: "⌘4" },
    "Reader" => { subtitle: "Feeds from your hobbies" },
    "Address Book" => { subtitle: "Contacts & directory", badge: "Vault" },
    "Photos" => { subtitle: "Photo library & memories", badge: "Vault" },
    "Documents" => { subtitle: "Files & attachments", badge: "Vault" },
    "Notes" => { subtitle: "Quick notes & drafts", badge: "Vault" },
    "Mail" => { subtitle: "Inbox & messages", badge: "Vault" },
    "Passwords" => { subtitle: "Credentials & security", badge: "Vault" }
  }.freeze

  # `count:` is a number that rides at the end of the row — the unread pile
  # behind a destination, which is the thing that makes anybody open it.
  # Deliberately not called `badge:`: that word is already taken here for
  # the tooltip's *kind* label ("Vault", "Today"), and one keyword meaning
  # two things is how a helper becomes a puzzle. Zero doesn't draw, and the
  # count carries `nav-label` so it disappears with the labels when the rail
  # is collapsed rather than sitting alone beside an icon.
  def nav_link_to(name, path, icon_name, subtitle: nil, badge: nil, shortcut: nil, count: nil)
    active = nav_active?(path)
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    meta = NAV_METADATA[name] || {}
    sub_text = subtitle || meta[:subtitle]
    badge_text = badge || meta[:badge]
    shortcut_text = shortcut || meta[:shortcut]

    data = {
      controller: "tooltip",
      tooltip_title_value: name
    }
    data[:tooltip_subtitle_value] = sub_text if sub_text.present?
    data[:tooltip_badge_value] = badge_text if badge_text.present?
    data[:tooltip_shortcut_value] = shortcut_text if shortcut_text.present?

    link_to path, class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}", data: data do
      parts = [ icon(icon_name, css_class: "size-4.5 shrink-0"), tag.span(name, class: "nav-label") ]
      if count.to_i.positive?
        count_classes = active ? "bg-primary-50/25 text-primary-50" : "bg-canvas text-soft"
        parts << tag.span(count, class: "nav-label ml-auto rounded-full px-1.5 text-xs tabular-nums #{count_classes}")
      end
      safe_join(parts)
    end
  end

  # One count per page render, memoized: the rail is on every page, and the
  # reader's unread pile is not worth a query per link.
  def reader_unread_count
    @reader_unread_count ||= FeedItem.where(feed: Current.user.feeds.active).unread.count
  end

  def section_nav_link(section)
    active = request.path == section_path(section.slug)
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    sub_text = section.parent ? "#{section.parent.name} section" : "Life Lens section"

    data = {
      controller: "tooltip",
      tooltip_title_value: section.name,
      tooltip_subtitle_value: sub_text,
      tooltip_badge_value: "Section"
    }

    link_to section_path(section.slug), class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}", data: data do
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
