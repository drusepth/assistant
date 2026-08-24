# Regenerates db/datasets/places.csv — the gazetteer the photo map names its
# pins from (docs/TRAVEL.md §2).
#
# The map refuses to geocode against a lookup service: the request log of a
# reverse-geocoder pointed at a photo library is the owner's itinerary, and a
# self-hosted app shouldn't need the network to tell its owner where they
# have been. So the gazetteer ships in the repo like the basemap, on the
# D-public-datasets layer — which also means an admin can replace it with a
# denser one without a new release.
#
# Source: Natural Earth 1:10m populated places (public domain, no attribution
# required). ~7,300 settlements: every capital, every large city, and a long
# tail of towns. Deliberately coarse — this names a pin, it does not resolve
# a street address, and a bigger file would buy precision the map has no way
# to show.
#
#   ruby script/build_places_dataset.rb [geojson-path-or-url]
require "csv"
require "yaml"
require "json"
require "net/http"
require "uri"

SOURCE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places_simple.geojson".freeze
OUTPUT = File.expand_path("../db/datasets/places.csv", __dir__)

# The one country whose formal name is long enough to crowd a pin label out
# of a tile. Everything else keeps the source's own spelling — this is a
# display shortening, not an opinion about names.
COUNTRY_ALIASES = { "United States of America" => "United States" }.freeze

source = ARGV.first || SOURCE
raw = source.start_with?("http") ? Net::HTTP.get(URI(source)) : File.read(source)
features = JSON.parse(raw.dup.force_encoding(Encoding::UTF_8)).fetch("features")

rows = features.filter_map do |feature|
  properties = feature["properties"]
  longitude, latitude = feature.dig("geometry", "coordinates")
  name = properties["name"].to_s.strip
  country = properties["adm0name"].to_s.strip
  country = COUNTRY_ALIASES.fetch(country, country)
  next if name.empty? || longitude.nil? || latitude.nil?

  # Four decimals is ~11m — far finer than a gazetteer entry means anyway,
  # and it keeps the file a third smaller than the source's 15 digits.
  [ name, country, latitude.round(4), longitude.round(4), properties["pop_max"].to_i ]
end

# Sorted so a regenerated file diffs as the handful of settlements that
# actually changed, rather than as 7,000 reordered lines.
rows.sort_by! { |name, country, *| [ country, name ] }

CSV.open(OUTPUT, "w", write_headers: true,
  headers: %w[ name country latitude longitude population ]) do |csv|
  rows.each { |row| csv << row }
end

File.write(OUTPUT.sub(/\.csv\z/, ".yml"), {
  "source" => "Natural Earth 1:10m populated places (public domain)",
  "url" => SOURCE,
  "places" => rows.size
}.to_yaml)

puts "Wrote #{OUTPUT}: #{rows.size} places, #{(File.size(OUTPUT) / 1024.0).round(1)} KB"
