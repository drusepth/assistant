module Ui
  # The world map of geotagged photos (D-travel-facet): a land silhouette
  # that ships in the repo, with one pin per place the viewer has
  # photographed. No tiles, no third party, no JavaScript — a pin is a link
  # to that place's photos, so the map works the same in a browser with
  # scripting off as in one with it on.
  class PhotoMapComponent < ApplicationComponent
    WORLD_LAND_FILE = Rails.root.join("app/assets/images/world_land.svg")
    DETAIL_LAND_FILE = Rails.root.join("app/assets/images/world_land_detail.svg")

    # The land silhouette as bare <path>s, for the map to wrap in its own
    # <svg>: the files' viewBox is the whole world, while a rendered map's is
    # whichever window Photos::Map settled on.
    #
    # Inlined rather than served as an <img> so the land takes its fill from
    # the stylesheet (`currentColor`) — the basemap carries shape, and the
    # palette stays in the token file where docs/DESIGN.md promises it lives.
    def self.world_land_path
      @world_land_path ||= WORLD_LAND_FILE.read[%r{<path\b[^>]*/>}].to_s.html_safe
    end

    # The detailed coastline, cut into grid cells at generation time and
    # parsed once per process into [bounding box, element] pairs. Natural
    # Earth's land is a handful of enormous rings — Afro-Eurasia is one
    # polygon — so without the cells, showing Portugal would mean emitting
    # half the planet.
    def self.detail_cells
      @detail_cells ||= DETAIL_LAND_FILE.read.scan(%r{(<path data-b="([^"]+)"[^>]*/>)}).map do |element, bounds|
        [ bounds.split.map(&:to_f), element ]
      end
    rescue SystemCallError
      []
    end

    def initialize(map:)
      @map = map
    end

    attr_reader :map

    # Coarse coastline for the world, detailed for anything zoomed in — at
    # country zoom the 110m outline is a blob with straight edges. Falls back
    # to the world path if the detail file is missing or the window somehow
    # touches no cell, so a map is never simply blank.
    def land
      return self.class.world_land_path unless map.zoomed?

      left, top, width, height = map.window_box
      cells = self.class.detail_cells.filter_map do |(x1, y1, x2, y2), element|
        element unless x2 < left || x1 > left + width || y2 < top || y1 > top + height
      end
      cells.any? ? cells.join.html_safe : self.class.world_land_path
    end

    # Dots are sized by how much happened there, not by zoom: a single
    # photo is a speck, a fortnight in one city is a disc worth its count.
    def pin_classes(pin)
      case pin.count
      when 1 then "size-2.5"
      when 2..9 then "size-3.5"
      else "size-5 text-[9px] font-semibold text-white"
      end
    end

    def pin_count_label(pin)
      return nil if pin.count < 10

      pin.count > 99 ? "99+" : pin.count.to_s
    end

    # Bigger pins draw first so a lone speck on top of a city stays
    # clickable.
    def ordered_pins = map.pins.sort_by { |pin| -pin.count }

    # What the map says, for anyone who can't see it.
    def summary
      "Map of #{pluralize(map.photo_count, "photo")} across " \
        "#{pluralize(map.place_count, "place")}. Each pin links to the photos taken there."
    end
  end
end
