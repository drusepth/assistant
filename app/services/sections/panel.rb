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
      "Sections::Panels::#{section.slug.camelize}".safe_constantize
        &.new(section: section, viewer: viewer)
    end

    attr_reader :section, :viewer

    def initialize(section:, viewer:)
      @section = section
      @viewer = viewer
    end

    # Tool slugs the panel already carries prefilled; the Act zone drops
    # their cards.
    def hidden_tool_slugs = []

    def partial = "sections/panels/#{section.slug}"
  end
end
