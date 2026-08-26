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

    # By slug first. Failing that, a parent may claim its user-created
    # lenses as a class — `Sections::Panels::PeopleLens` for every group
    # under People (D-people-circles) — since those slugs are named by the
    # user and can't be known here. A parent that declares no such class
    # keeps the old answer: no panel, generic page.
    def self.panel_class(section)
      "Sections::Panels::#{section.slug.camelize}".safe_constantize ||
        (section.parent && "Sections::Panels::#{section.parent.slug.camelize}Lens".safe_constantize)
    end

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

    def partial = "sections/panels/#{section.slug}"
  end
end
