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

    # By slug first. Then a lens a model owns — a `Pet` holds a custom child
    # of Pets (`Section::LENS_OWNERS`), and without this rung Rex's lens
    # would fall through to the parent rule below and find no panel. Failing both, a parent may
    # claim its user-created lenses as one class, since those slugs are named
    # by the user and can't be known here: `Panels::PeopleLens` for every
    # group under People (D-people-circles), `Panels::HobbiesLens` for every
    # hobby's river (D-hobby-feeds). A parent that declares no such class
    # keeps the old answer: no panel, generic page.
    #
    # Two branches arrived at the parent fallback for their own section in the
    # same week, which is the argument for it being here rather than in either.
    def self.panel_class(section)
      constant(section.slug) || owned_lens_class(section) ||
        (section.parent && constant("#{section.parent.slug}_lens"))
    end

    # `Pet` => `Sections::Panels::PetLens`, by the same naming convention the
    # parent fallback uses.
    def self.owned_lens_class(section)
      section.lens_owner&.then { |model| constant("#{model.underscore}_lens") }
    end
    private_class_method :owned_lens_class

    # Lens slugs are `parameterize`d, so they hyphenate ("board-games") where
    # a constant needs underscores — `camelize` alone leaves "Board-games"
    # and silently finds nothing.
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

    # Whether the browse zone's "Nothing in <Section> yet" card draws when
    # the lens is empty. A hub whose panel already leads with the section's
    # own records (Pets' pet cards) turns it off: under a pet card, "nothing
    # here" reads as if the pet didn't count, and the card itself is the
    # better way in.
    def show_empty_browse? = true

    # Named after the panel rather than the section: they are the same
    # string for every seeded section (`Panels::Health` → `_health`), and a
    # lens panel serves many sections at once.
    def partial = "sections/panels/#{self.class.name.demodulize.underscore}"
  end
end
