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
    assert_equal "3 photos · Jun 2019 – Aug 2019", map.pins.first.label
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
