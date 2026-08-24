# Regenerates app/assets/images/world_land.svg — the land outline the photo
# map is drawn on (docs/TRAVEL.md).
#
# The app draws its own basemap rather than pulling tiles from a map host:
# a self-hosted life assistant shouldn't have to phone a third party (and
# hand it a trace of where its owner has been) just to show its owner a map
# of their own photos. That means the geometry ships in the repo, and this
# script is how it got there.
#
# Source: Natural Earth 1:110m "land" vectors — public domain, no attribution
# required ("Made with Natural Earth"). The 110m scale is the coarse one on
# purpose: at world zoom a coastline is a silhouette, and every extra vertex
# is bytes on a page that has to render on a phone.
#
#   ruby script/build_world_map.rb [110m-geojson] [50m-geojson]
#
# Two files come out of it, because one basemap cannot serve both zooms:
#
# * `world_land.svg` — 1:110m, one path, the whole world. What the world view
#   draws, where a coastline is a silhouette and every extra vertex is bytes
#   on a page that has to render on a phone.
# * `world_land_detail.svg` — 1:50m, cut into a grid of cells, each a path
#   carrying its own bounding box in `data-b`. Zoomed views (a trip, a
#   country) emit only the cells that intersect the window, so the page
#   carries the coastline it is showing and not the other 95% of the planet.
#   At country zoom the 110m outline is a blob with straight edges; this is
#   the fix.
#
#   Cutting happens here rather than at render time because Natural Earth's
#   land is a handful of enormous rings — Afro-Eurasia is one polygon — so
#   "emit the rings in view" would emit half the planet to show Portugal.
#   Each ring is clipped (Sutherland–Hodgman) to every cell it touches, and a
#   cell's rings share one path with `fill-rule="evenodd"` so lakes stay
#   holes instead of becoming islands.
#
# Output is an equirectangular (plate carrée) SVG on a 1000×500 viewBox, so
# the projection Photos::Map uses is the trivial one:
#
#   x = (lon + 180) / 360 * 1000        y = (90 - lat) / 180 * 500
#
# Land is filled with `currentColor` so the map takes its color from the
# stylesheet like everything else in the design system — the asset carries
# shape, never palette.
require "json"
require "net/http"
require "uri"

BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson".freeze
IMAGES = File.expand_path("../app/assets/images", __dir__)

WIDTH = 1000.0
HEIGHT = 500.0

# Douglas-Peucker tolerance and minimum ring size, in map units (1 unit =
# 0.36° ≈ 40km at the equator), per output. The world view can afford to be
# coarse and can't afford the bytes; the detail view is the opposite, and
# only ships the rings in view anyway.
SCALES = {
  world: { source: "ne_110m_land.geojson", output: "world_land.svg",
           tolerance: 0.35, min_extent: 0.6, per_ring: false },
  detail: { source: "ne_50m_land.geojson", output: "world_land_detail.svg",
            tolerance: 0.05, min_extent: 0.15, per_ring: true }
}.freeze

# Grid cell size in map units (27.8 ≈ 10°). A zoomed window is a dozen units
# across, so it touches at most four cells.
CELL = 27.8
# Cells are clipped very slightly oversized so neighbours overlap instead of
# abutting: two filled shapes meeting on an exact edge leave a one-pixel
# anti-aliasing seam, which reads as a crack across the land. The overlap is
# invisible — same fill, same colour — and under a pixel at the deepest zoom.
CELL_BLEED = 0.03

def project(lon, lat)
  [ (lon + 180.0) / 360.0 * WIDTH, (90.0 - lat) / 180.0 * HEIGHT ]
end

# Iterative Douglas-Peucker: keep the vertex furthest from the chord while it
# is further than the tolerance, recurse on both halves.
def simplify(points, tolerance)
  return points if points.size < 3

  first, last = points.first, points.last
  index, distance = 0, 0.0

  points.each_with_index do |point, i|
    next if i.zero? || i == points.size - 1

    d = perpendicular_distance(point, first, last)
    index, distance = i, d if d > distance
  end

  if distance > tolerance
    simplify(points[0..index], tolerance)[0..-2] + simplify(points[index..], tolerance)
  else
    [ first, last ]
  end
end

def perpendicular_distance(point, line_start, line_end)
  x, y = point
  x1, y1 = line_start
  x2, y2 = line_end
  dx, dy = x2 - x1, y2 - y1

  return Math.hypot(x - x1, y - y1) if dx.zero? && dy.zero?

  t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)
  t = t.clamp(0.0, 1.0)
  Math.hypot(x - (x1 + t * dx), y - (y1 + t * dy))
end

def rings(geometry)
  case geometry["type"]
  when "Polygon" then geometry["coordinates"]
  when "MultiPolygon" then geometry["coordinates"].flatten(1)
  else []
  end
end

# The detail file needs a decimal place the world file doesn't: at country
# zoom, rounding to 0.1 units (4km) is a visible staircase.
def points_for(ring, tolerance:, min_extent:, precision:)
  points = ring.map { |lon, lat| project(lon, lat) }
  points = simplify(points, tolerance).map { |x, y| [ x.round(precision), y.round(precision) ] }
  points = points.chunk_while { |a, b| a == b }.map(&:first)
  return nil if points.size < 4

  xs, ys = points.transpose
  return nil if (xs.max - xs.min) < min_extent && (ys.max - ys.min) < min_extent

  points
end

def path_data(points)
  coords = points.map { |x, y| "#{trim(x)} #{trim(y)}" }
  "M#{coords.first}L#{coords[1..].join("L")}Z"
end

def bbox_of(points)
  xs, ys = points.transpose
  [ xs.min, ys.min, xs.max, ys.max ]
end

# Sutherland–Hodgman against an axis-aligned rectangle: clip the polygon by
# each of the four edges in turn. Degenerate edges run along the cell
# boundary, which is invisible in a fill with no stroke — and neighbouring
# cells meet exactly there, so the land reads as one piece.
def clip(points, left, top, right, bottom)
  [ [ :x, left, 1 ], [ :x, right, -1 ], [ :y, top, 1 ], [ :y, bottom, -1 ] ]
    .reduce(points) do |polygon, (axis, value, sign)|
      break [] if polygon.empty?

      index = axis == :x ? 0 : 1
      inside = ->(point) { (point[index] - value) * sign >= 0 }
      clipped = []

      polygon.each_with_index do |current, i|
        previous = polygon[i - 1]
        if inside.call(current)
          clipped << intersect(previous, current, index, value) unless inside.call(previous)
          clipped << current
        elsif inside.call(previous)
          clipped << intersect(previous, current, index, value)
        end
      end
      clipped
    end
end

def intersect(from, to, index, value)
  span = to[index] - from[index]
  t = span.zero? ? 0.0 : (value - from[index]) / span
  [ (from[0] + ((to[0] - from[0]) * t)).round(2), (from[1] + ((to[1] - from[1]) * t)).round(2) ]
end

def trim(value)
  value == value.to_i ? value.to_i.to_s : value.to_s
end

def load(source)
  raw = source.start_with?("http") ? Net::HTTP.get(URI(source)) : File.read(source)
  JSON.parse(raw).fetch("features")
end

SCALES.each_with_index do |(_scale, config), index|
  source = ARGV[index] || "#{BASE}/#{config[:source]}"
  precision = config[:per_ring] ? 2 : 1
  polygons = load(source).flat_map { |feature| rings(feature["geometry"]) }
    .filter_map { |ring| points_for(ring, tolerance: config[:tolerance], min_extent: config[:min_extent], precision: precision) }

  body =
    if config[:per_ring]
      cells = Hash.new { |hash, key| hash[key] = [] }
      polygons.each do |points|
        left, top, right, bottom = bbox_of(points)
        ((left / CELL).floor..(right / CELL).floor).each do |column|
          ((top / CELL).floor..(bottom / CELL).floor).each do |row|
            piece = clip(points, (column * CELL) - CELL_BLEED, (row * CELL) - CELL_BLEED,
              ((column + 1) * CELL) + CELL_BLEED, ((row + 1) * CELL) + CELL_BLEED)
            cells[[ column, row ]] << piece if piece.size >= 3
          end
        end
      end

      cells.sort.map do |(column, row), pieces|
        bbox = [ column * CELL, row * CELL, (column + 1) * CELL, (row + 1) * CELL ]
          .map { |value| trim(value.round(1)) }.join(" ")
        %(<path data-b="#{bbox}" d="#{pieces.map { |piece| path_data(piece) }.join}"/>)
      end.join("\n")
    else
      %(<path fill="currentColor" fill-rule="evenodd" d="#{polygons.map { |points| path_data(points) }.join}"/>)
    end

  output = File.join(IMAGES, config[:output])
  count = config[:per_ring] ? body.scan("<path").size : polygons.size
  File.write(output, <<~SVG)
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{WIDTH.to_i} #{HEIGHT.to_i}" preserveAspectRatio="none" aria-hidden="true" focusable="false">
    <!-- Generated by script/build_world_map.rb from Natural Earth #{config[:source]} (public domain). Do not hand-edit. -->
    #{body}
    </svg>
  SVG

  puts "Wrote #{output}: #{count} #{config[:per_ring] ? "cells" : "rings"}, #{(File.size(output) / 1024.0).round(1)} KB"
end
