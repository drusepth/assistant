module Ui
  # A page-header quick-add button whose capture form opens as a dropdown
  # panel anchored beneath it (a sheet pinned under the top bar on small
  # screens). Each instance carries its own `quick-add` controller, so it
  # drops into any page without a wrapper; opening one closes every other
  # one on the page through a window event. Most callers want the
  # `quick_add` helper (QuickAddHelper), which builds the record, picks the
  # capture form, and points `full_form_url:` at the new-item page.
  #
  # `full_form_url:` adds a "Full form" link to the panel's header — the
  # way out to the standalone page when the dropdown isn't enough.
  #
  # `align:` says which edge of the button the panel hangs from at `sm` and
  # up: `:end` (the default — header actions sit at the right of the page),
  # `:start` for a button near the left edge, `:center` for a centered row
  # like an empty state's actions.
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
    ALIGNMENTS = {
      start: "sm:left-0",
      center: "sm:left-1/2 sm:-translate-x-1/2",
      end: "sm:right-0"
    }.freeze

    def initialize(name:, label:, title:, icon: :plus, primary: false, tile: false, small: false,
                   full_form_url: nil, align: :end)
      @full_form_url = full_form_url
      @align = ALIGNMENTS.fetch(align)
      @name = name
      @label = label
      @title = title
      @icon = icon
      @primary = primary
      @tile = tile
      @small = small
    end

    attr_reader :name, :label, :title, :icon, :full_form_url

    def panel_classes
      "hidden fixed inset-x-3 top-20 z-30 card p-5 shadow-lg sm:absolute sm:inset-x-auto #{@align} " \
        "sm:top-full sm:mt-2 sm:w-96 sm:max-w-[calc(100vw-3rem)]"
    end

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
