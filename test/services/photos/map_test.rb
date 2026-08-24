require "test_helper"

class Photos::MapTest < ActiveSupport::TestCase
  # Real places, so the clustering distances in the assertions are real
  # distances rather than numbers chosen to make the test pass.
  PARIS = [ 48.8566, 2.3522 ]
  LOUVRE = [ 48.8606, 2.3376 ]
  LONDON = [ 51.5072, -0.1276 ]
  SYDNEY = [ -33.8688, 151.2093 ]
  MCMURDO = [ -77.8419, 166.6863 ]

  test "photos in one spot become one pin carrying the count and the date range" do
    place(PARIS, taken_at: Time.zone.parse("2019-06-01 10:00"))
    place(LOUVRE, taken_at: Time.zone.parse("2019-06-03 10:00"))
    place(PARIS, taken_at: Time.zone.parse("2019-08-20 10:00"))

    map = Photos::Map.new(users(:one).photos)

    assert_equal 1, map.place_count
    assert_equal 3, map.photo_count
    assert_equal 3, map.pins.first.count
    assert_equal "Paris · 3 photos · Jun 2019 – Aug 2019", map.pins.first.label
  end

  test "cities an hour apart stay separate pins" do
    place(PARIS)
    place(LONDON)

    assert_equal 2, Photos::Map.new(users(:one).photos).place_count
  end

  test "a photo with no coordinates is not on the map" do
    place(PARIS)
    users(:one).photos.create!(image: image_fixture)

    map = Photos::Map.new(users(:one).photos)
    assert_equal 1, map.photo_count
  end

  test "coordinates are owner-only, so another member's photos never place" do
    place(PARIS, user: users(:two))

    assert_not Photos::Map.new(users(:one).photos).any?
  end

  test "a pin sits where its photos are, in percentages of the rendered map" do
    place([ 0.0, 0.0 ])

    map = Photos::Map.new(users(:one).photos)
    position = map.position(map.pins.first)

    # 0°E is the middle of a map that runs -180…180.
    assert_equal "50.0%", position[:left]
    # The equator is below the middle of the default window, which crops
    # more off the south than the north.
    assert_operator position[:top].to_f, :>, 50.0
    assert_operator position[:top].to_f, :<, 70.0
  end

  test "the default window crops the empty polar bands" do
    place(PARIS)

    assert_equal "0 22.22 1000 388.89", Photos::Map.new(users(:one).photos).view_box
  end

  test "a photo outside the default window widens it rather than falling off the map" do
    place(MCMURDO)

    map = Photos::Map.new(users(:one).photos)
    top = map.view_box.split.second.to_f
    height = map.view_box.split.fourth.to_f

    assert_operator top + height, :>, 411.11
    position = map.position(map.pins.first)
    assert_operator position[:top].to_f, :<=, 100.0
  end

  test "each pin carries its newest photo as the thumbnail" do
    place(PARIS, taken_at: Time.zone.parse("2019-06-01 10:00"))
    newest = place(LOUVRE, taken_at: Time.zone.parse("2019-06-03 10:00"))

    assert_equal newest, Photos::Map.new(users(:one).photos).pins.first.cover
  end

  test "recent pins lead with the place you were at most recently" do
    place(PARIS, taken_at: 3.years.ago)
    place(SYDNEY, taken_at: 1.week.ago)

    assert_in_delta SYDNEY.first, Photos::Map.new(users(:one).photos).recent_pins.first.latitude, 0.01
  end

  test "a pin's near link finds exactly its own photos" do
    place(PARIS)
    place(LOUVRE)
    place(LONDON)

    pin = Photos::Map.new(users(:one).photos).pins.find { |candidate| candidate.count == 2 }
    latitude, longitude = pin.near_param.split(",").map(&:to_f)

    assert_equal 2, users(:one).photos.near(latitude, longitude).count
  end

  test "pins are named from the local gazetteer, and grouped by country" do
    place(PARIS)
    place(LOUVRE)
    place(LONDON)

    map = Photos::Map.new(users(:one).photos)
    paris = map.pins.find { |pin| pin.count == 2 }

    assert_equal "Paris", paris.place_name
    assert_equal "Paris", paris.heading
    assert_equal "Paris · 2 photos · #{paris.period}", paris.label
    assert_equal [ "France", "United Kingdom" ], map.by_country.map(&:first).sort
  end

  test "a pin the gazetteer can't place falls back to when, not to a guess" do
    place([ 0.0, -140.0 ], taken_at: Time.zone.parse("2019-06-01 10:00")) # mid-Pacific

    pin = Photos::Map.new(users(:one).photos).pins.first

    assert_nil pin.place_name
    assert_equal "Jun 2019", pin.heading
    assert_equal "1 photo · Jun 2019", pin.label
    assert_equal [ nil ], Photos::Map.new(users(:one).photos).by_country.map(&:first)
  end

  test "zooming in separates cities that share a pin at world scale" do
    place(PARIS)
    place([ 49.4431, 1.0993 ]) # Rouen — 110km from Paris, one pin at world zoom

    world = Photos::Map.new(users(:one).photos)
    assert_equal 1, world.place_count

    zoomed = Photos::Map.new(users(:one).photos,
      bounds: { south: 48.0, west: 0.5, north: 50.0, east: 3.0 })
    assert_equal 2, zoomed.place_count, "the clustering radius is a distance on screen, not on Earth"
    assert_predicate zoomed, :zoomed?
    assert_not world.zoomed?
  end

  test "a zoomed map reads only the photos in its window" do
    place(PARIS)
    place(SYDNEY)

    zoomed = Photos::Map.new(users(:one).photos,
      bounds: { south: 48.0, west: 1.0, north: 50.0, east: 3.0 })

    assert_equal 1, zoomed.photo_count
  end

  test "a zoomed window is padded and never squashed" do
    place(PARIS)
    place([ 41.1579, -8.6291 ]) # Porto — a tall, thin box

    map = Photos::Map.new(users(:one).photos,
      bounds: { south: 41.1579, west: -9.14, north: 48.8566, east: -0.1 })
    _x, _y, width, height = map.window_box

    assert_operator map.aspect_ratio, :>=, Photos::Map::MIN_ASPECT
    assert_operator map.aspect_ratio, :<=, Photos::Map::TARGET_ASPECT
    assert_operator width, :<, Photos::Map::WIDTH
    assert_operator height, :>, 0
    # Every pin still inside the padded window.
    map.pins.each do |pin|
      assert_operator map.position(pin)[:left].to_f, :>, 0
      assert_operator map.position(pin)[:left].to_f, :<, 100
    end
  end

  test "a zoomed map is lettered with nearby place names, the world map isn't" do
    place(PARIS)

    zoomed = Photos::Map.new(users(:one).photos,
      bounds: { south: 48.0, west: 1.0, north: 50.0, east: 3.5 })
    names = zoomed.context_labels.map(&:name)

    assert_includes names, "Rouen", "a zoomed map says what's around it"
    assert_not_includes names, "Paris", "lettering gives way where a pin already names the place"
    assert_empty Photos::Map.new(users(:one).photos).context_labels,
      "the world map is pins, not a gazetteer dump"
  end

  test "a country's pins hand their own corner of the world to a zoom link" do
    place(PARIS)
    place(LONDON)

    map = Photos::Map.new(users(:one).photos)
    france = map.by_country.to_h.fetch("France")

    assert_equal "48.8566,2.3522,48.8566,2.3522", Photos::Map.bbox_for(france)
  end

  # The map's cost is dominated by what a row costs to build, and a plain
  # pluck of these columns hands back a BigDecimal per coordinate and a
  # TimeWithZone per photo — 750ms of allocation on a 60,000-photo library,
  # for values the map immediately treats as numbers. This pins the casts so
  # a tidy-up can't quietly put them back (script/benchmark_photo_map.rb).
  test "rows come out of SQL as primitives, not as objects to be discarded" do
    place(PARIS)

    id, latitude, longitude, at = Photos::Map.new(users(:one).photos).rows.first

    assert_kind_of Integer, id
    assert_kind_of Float, latitude
    assert_kind_of Float, longitude
    assert_kind_of Integer, at, "timestamps stay epoch seconds until something prints one"
  end

  test "an empty library is an empty map, not an error" do
    map = Photos::Map.new(users(:one).photos)

    assert_not map.any?
    assert_equal 0, map.place_count
    assert_nil map.first_taken_at
    assert_predicate map.aspect_ratio, :positive?
  end

  private
    def place((latitude, longitude), user: users(:one), taken_at: Time.current)
      user.photos.create!(image: image_fixture, latitude: latitude, longitude: longitude,
        taken_at: taken_at)
    end

    def image_fixture
      { io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg" }
    end
end
