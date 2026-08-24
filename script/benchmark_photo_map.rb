# What the photo map costs on a library the size of a real one.
#
#   bin/rails runner script/benchmark_photo_map.rb [size]
#
# Inserts synthetic photos for the first user inside a transaction and rolls
# it back, so it is safe to run against a real database — nothing is kept.
# No attachments: the map reads four columns and never touches a blob.
#
# The numbers this was written for (2026-08, laptop-class hardware, SQLite):
#
#     60,000 photos | rows 134ms | pins 355ms | trips 193ms | travel page 706ms
#     20,000 photos | rows  40ms | pins  98ms | trips  65ms | travel page 234ms
#
# If the page is ever the thing that needs fixing, the next lever is letting
# SQLite do the grouping — `GROUP BY round(latitude, 1), round(longitude, 1)`
# and a day column would hand Ruby a few thousand rows instead of sixty
# thousand. It is a real rewrite of both services, so it waits for a library
# that actually hurts.
require "benchmark"

size = (ARGV.first || 60_000).to_i
user = User.first
abort "No users on this instance." unless user

ActiveRecord::Base.transaction do
  random = Random.new(42)
  places = 40.times.map { [ random.rand(-55.0..65.0), random.rand(-170.0..170.0) ] }
  home = [ 51.5072, -0.1276 ]
  now = Time.current

  # Photos arrive in bursts — a day at home, a week abroad — not alternating
  # between continents every shot. A benchmark that shuffles them measures a
  # library nobody has.
  rows = []
  batch = 0
  while rows.size < size
    at_home = (batch % 4) != 3
    latitude, longitude = at_home ? home : places[batch % places.size]
    (at_home ? random.rand(5..60) : random.rand(20..200)).times do
      rows << { user_id: user.id,
                latitude: latitude + random.rand(-0.05..0.05),
                longitude: longitude + random.rand(-0.05..0.05),
                taken_at: now - (rows.size * 37).minutes,
                created_at: now, updated_at: now }
    end
    batch += 1
  end
  rows.first(size).each_slice(5_000) { |slice| Photo.insert_all(slice) }
  puts "#{Photo.where(user_id: user.id).located.count} located photos"

  map = Photos::Map.new(user.photos)
  timings = {
    "rows (SQL + casting)" => Benchmark.realtime { map.rows },
    "pins (clustering)" => Benchmark.realtime { map.pins },
    "by_country" => Benchmark.realtime { map.by_country },
    "trips (detection)" => Benchmark.realtime { Travel::Trips.new(map).candidates },
    "zoomed map" => Benchmark.realtime do
      Photos::Map.new(user.photos, bounds: { south: 38.0, west: -10.0, north: 42.0, east: -8.0 }).pins
    end
  }
  timings.each { |label, seconds| puts format("  %-22s %6.0fms", label, seconds * 1000) }
  puts format("  %-22s %6d", "places found", map.place_count)

  raise ActiveRecord::Rollback
end
