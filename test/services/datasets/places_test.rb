require "test_helper"

class Datasets::PlacesTest < ActiveSupport::TestCase
  # Against the real shipped gazetteer: a fixture would test the lookup and
  # not the data, and the data is half of what can go wrong here.
  setup { @places = Datasets::Places.current }

  test "the shipped gazetteer loads" do
    assert_predicate @places, :present?
    assert_operator @places.size, :>, 5_000
  end

  test "coordinates in a city are that city, named plainly" do
    match = @places.nearest(48.8566, 2.3522)

    assert_equal "Paris", match.name
    assert_equal "France", match.country
    assert_not match.near?
    assert_equal "Paris, France", match.qualified
  end

  test "coordinates out in the country are hedged, not claimed" do
    match = @places.nearest(44.0, -110.0) # Wyoming backcountry

    assert match.near?, "50+ km from the nearest town should not claim to be it"
    assert_match(/\ANear /, match.label)
    assert_operator match.distance_km, :>, Datasets::Places::EXACT_KM
  end

  test "the middle of the Pacific gets no name at all" do
    assert_nil @places.nearest(0.0, -140.0)
  end

  test "the nearest match wins, not the most famous" do
    # Brooklyn is closer to New York than to anywhere else on file.
    assert_equal "New York", @places.nearest(40.6782, -73.9442).name
    # Kyoto is 40km from Osaka; a naive population sort would answer Osaka.
    assert_equal "Kyoto", @places.nearest(35.0116, 135.7681).name
  end

  test "a longitude near the antimeridian still matches across it" do
    # Labasa sits at 179.38°E. A photo just over the date line at 179.9°W is
    # ~77km away, not 359° away — the longitude pre-filter has to know that.
    match = @places.nearest(-16.42, -179.9)

    assert_equal "Labasa", match.name
    assert_operator match.distance_km, :<=, Datasets::Places::NEAR_KM
  end

  test "named finds a place by typed text, biggest population winning a bare name" do
    match = Datasets::Places.current.named("Portland")
    assert_equal "United States", match.country
    assert_in_delta 45.52, match.latitude, 0.1, "a bare Portland is Oregon's"

    assert_equal "Australia", Datasets::Places.current.named("Portland, Australia").country
  end

  test "named ignores a qualifier it can't use, and admits what it doesn't know" do
    # The file knows countries, not states — "Boise, Idaho" still finds Boise.
    match = Datasets::Places.current.named("Boise, Idaho")
    assert_equal "Boise", match.name

    assert_nil Datasets::Places.current.named("The A-frame on Route 9")
    assert_nil Datasets::Places.current.named("")
    assert_nil Datasets::Places.new(path: nil).named("Lisbon")
  end

  test "a missing gazetteer is an unnamed map, never an error" do
    empty = Datasets::Places.new(path: nil)

    assert_not_predicate empty, :present?
    assert_nil empty.nearest(48.8566, 2.3522)
  end

  test "a malformed gazetteer degrades the same way" do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("places.csv")
      path.write("name,country,latitude,longitude,population\nnowhere,,,,\n")

      assert_nil Datasets::Places.new(path: path).nearest(48.8566, 2.3522)
    end
  end
end
