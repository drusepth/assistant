module LifeSectionsHelper
  # The one line that says what a section is for. The /about hubs already
  # wrote it for every seeded section, so the picker borrows it rather than
  # keeping a second copy; a section without a hub (a newer one, or a
  # future pack) falls back to naming what's inside it.
  def life_section_blurb(section)
    About::Page::HUBS.find { |hub| hub.slug == section.slug }&.blurb ||
      section.children.map(&:name).join(" · ").presence
  end

  def life_section_hub?(section)
    About::Page::HUBS.any? { |hub| hub.slug == section.slug }
  end
end
