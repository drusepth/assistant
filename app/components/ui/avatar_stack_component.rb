module Ui
  # Layered faces for a group of people (D-people-circles): up to `max`
  # overlapping avatars and a `+N` bubble for the rest. A group *is* its
  # people, and a card showing four faces you recognize is a card you touch
  # — which is the whole argument for the circles grid.
  #
  # It renders *through* Ui::AvatarComponent rather than around it — one
  # face, one place (D-user-avatars) — so uploaded photos, linked-member
  # photos, and initials all behave here exactly as they do in a row.
  #
  # Consumers beyond the People page, so the ring/overlap math lives in one
  # place: photo album tiles (a photo's tagged people), household member
  # lists, and event attendees when Q17 lands.
  class AvatarStackComponent < ApplicationComponent
    # Cycled by person id, not by position: the same face keeps the same
    # tint on every card it appears in. Stone is deliberately not in the
    # cycle — it belongs to the `+N` bubble, which must not read as one
    # more face.
    TONES = %i[ primary amber sage ].freeze

    # Pulling the faces together by roughly a quarter of their width — any
    # more and the initials underneath stop being readable.
    OVERLAP = {
      xxs: "-space-x-1", xs: "-space-x-1.5", sm: "-space-x-2", md: "-space-x-2.5", lg: "-space-x-3.5"
    }.freeze

    # people: the faces to draw (already ordered — the caller decides whose
    #   five matter).
    # total: how many there are in all, when the caller fetched only a
    #   window. Defaults to what it was given.
    # ghost: with nobody to draw, hold the row's height with an empty
    #   dashed circle — so a card with no members still lines up with the
    #   cards beside it. `empty_label` adds words next to it; usually the
    #   caller's own copy already says it, and the ghost alone is enough.
    def initialize(people:, total: nil, size: :sm, max: 5, link: true, ghost: false, empty_label: nil)
      @people = people.to_a
      @total = total || @people.size
      @size = size
      @max = max
      @link = link
      @ghost = ghost
      @empty_label = empty_label
    end

    attr_reader :size, :empty_label

    def ghost? = @ghost || @empty_label.present?

    def shown = @shown ||= @people.first(@max)
    def any? = shown.any?
    def link? = @link
    def overflow = @total - shown.size

    def wrapper_classes = "flex items-center #{OVERLAP.fetch(size, "-space-x-2")}"

    # The ring is the card's own background, so the faces read as separated
    # layers rather than one smudge; the lift on hover says "this one is
    # its own door."
    def face_classes = "relative ring-2 ring-surface transition hover:z-10 hover:-translate-y-0.5"

    def bubble_classes
      # The one stone circle in the row: "+3" is a count, not a person, and
      # no face is tinted stone (see TONES) so it can't be mistaken for one.
      [ "relative flex shrink-0 items-center justify-center rounded-full bg-stone-100 font-semibold text-stone-600 ring-2 ring-surface",
        AvatarComponent::SIZES.fetch(size) ].join(" ")
    end

    def ghost_classes
      [ "shrink-0 rounded-full border border-dashed border-edge", AvatarComponent::SIZES.fetch(size) ].join(" ")
    end

    def tone_for(person) = TONES[person.id.to_i % TONES.size]
  end
end
