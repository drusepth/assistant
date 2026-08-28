module Ui
  # A page-header quick-add button whose capture form opens as a dropdown
  # panel anchored beneath it (a bottom sheet on small screens). Requires an
  # enclosing `data-controller="quick-add"` element, which coordinates
  # one-open-at-a-time across sibling instances.
  #
  # `tile: true` opts into the phone shape (`.btn-tile`): a stacked
  # icon-over-label tile sized for a 4-across grid, which folds back into
  # the ordinary pill from `sm` up. A row of them wants `icon:` too — the
  # tile shows the *kind* mark (a calendar for an event, a flag for a goal)
  # rather than four identical plus signs, with a plus badge keeping the
  # "add one" meaning.
  #
  # `small: true` is the card-header shape: a `btn-sm` pill for a
  # `card.with_actions` row, quiet enough to sit beside the card's other
  # small links without out-weighing the card's own title.
  class QuickAddComponent < ApplicationComponent
    def initialize(name:, label:, title:, icon: :plus, primary: false, tile: false, small: false)
      @name = name
      @label = label
      @title = title
      @icon = icon
      @primary = primary
      @tile = tile
      @small = small
    end

    attr_reader :name, :label, :title, :icon

    def tile? = @tile

    # The plus keeps step with the label it sits beside.
    def plus_classes = @small ? "size-3.5" : "size-4"

    def button_classes
      [ "btn", @primary ? "btn-primary" : "btn-secondary",
        ("btn-tile" if tile?), ("btn-sm" if @small) ].compact.join(" ")
    end

    # The disc reads on whatever the tile is filled with: a tint of the
    # accent on the secondary tiles, a lighter wash of white on the solid
    # primary one. Both are utilities, so they beat the atom's own fill at
    # the base width and hand back to it at `sm`, where there is no disc.
    def icon_classes
      [ "btn-tile-icon", ("bg-primary-50/25 text-primary-50 sm:bg-transparent" if @primary) ].compact.join(" ")
    end

    # The plus badge inverts with it, so it stays visible on a filled tile.
    def badge_classes
      @primary ? "bg-primary-50 text-primary-800 ring-primary-600" : "bg-primary-600 text-primary-50 ring-surface"
    end
  end
end
