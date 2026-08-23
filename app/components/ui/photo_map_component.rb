module Ui
  # The world map of geotagged photos (D-travel-facet): a land silhouette
  # that ships in the repo, with one pin per place the viewer has
  # photographed. No tiles, no third party, no JavaScript — a pin is a link
  # to that place's photos, so the map works the same in a browser with
  # scripting off as in one with it on.
  class PhotoMapComponent < ApplicationComponent
    WORLD_LAND_FILE = Rails.root.join("app/assets/images/world_land.svg")

    # The land silhouette as a bare <path>, for the map to wrap in its own
    # <svg>: the file's viewBox is the whole world, while a rendered map's
    # is whichever window Photos::Map settled on.
    #
    # Inlined rather than served as an <img> so the land takes its fill
    # from the stylesheet (`currentColor`) — the basemap carries shape, and
    # the palette stays in the token file where docs/DESIGN.md promises it
    # lives.
    def self.world_land_path
      @world_land_path ||= WORLD_LAND_FILE.read[%r{<path\b[^>]*/>}].html_safe
    end

    def world_land_path = self.class.world_land_path

    # Dots are sized by how much happened there, not by zoom: a single
    # photo is a speck, a fortnight in one city is a disc worth its count.
    def initialize(map:)
      @map = map
    end

    attr_reader :map

    # What the map says, for anyone who can't see it.
    def summary
      "Map of #{pluralize(map.photo_count, "photo")} across " \
        "#{pluralize(map.place_count, "place")}. Each pin links to the photos taken there."
    end

    def pin_classes(pin)
      case pin.count
      when 1 then "size-2.5"
      when 2..9 then "size-3.5"
      else "size-6 text-[10px] font-semibold text-white"
      end
    end

    def pin_count_label(pin)
      return nil if pin.count < 10

      pin.count > 99 ? "99+" : pin.count.to_s
    end

    # Bigger pins draw first so a lone speck on top of a city stays
    # clickable.
    def ordered_pins = map.pins.sort_by { |pin| -pin.count }
  end
end
