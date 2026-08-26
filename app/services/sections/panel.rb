module Sections
  # Per-section lead panels by convention (D37): building out a section
  # means adding `Sections::Panels::<Slug>` plus its partial at
  # `app/views/sections/panels/_<slug>.html.erb` — and never editing
  # SectionsController, sections/show.html.erb, or SectionsHelper. Those
  # three files were the merge hot spot when the Hobbies, subsection-tile,
  # and Health buildouts landed in parallel; under this convention,
  # parallel section buildouts touch disjoint files.
  #
  # A panel wraps everything section-specific the page needs: the data its
  # partial reads (as memoized methods) and the tool cards the Act zone
  # should hide because the panel surfaces them with better context.
  class Panel
    def self.for(section, viewer)
      panel_class(section)&.new(section: section, viewer: viewer)
    end

    # A section's own panel, or — for a user-created lens, whose slug no
    # class can be named after — its parent's lens panel. Hobbies registers
    # `Panels::HobbiesLens` and every hobby page gets a river (D-hobby-feeds);
    # People's groups get the same seam the day they want one.
    def self.panel_class(section)
      constant(section.slug) ||
        (section.parent && constant("#{section.parent.slug}_lens"))
    end

    def self.constant(slug)
      "Sections::Panels::#{slug.tr("-", "_").camelize}".safe_constantize
    end
    private_class_method :constant

    attr_reader :section, :viewer

    def initialize(section:, viewer:)
      @section = section
      @viewer = viewer
    end

    # Tool slugs the panel already carries prefilled; the Act zone drops
    # their cards.
    def hidden_tool_slugs = []

    # Generic browse cards the panel replaces with better-context versions
    # (symbols: :events, :people, …); the browse zone skips them. People
    # hides the roster grid this way — the Address Book is the roster (D-people-dashboard).
    def hidden_browse = []

    # Named after the panel rather than the section: they are the same
    # string for every seeded section (`Panels::Health` → `_health`), and a
    # lens panel serves many sections at once.
    def partial = "sections/panels/#{self.class.name.demodulize.underscore}"
  end
end
