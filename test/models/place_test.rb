require "test_helper"

# A place is a gazetteer-named point (D-place-subscriptions): resolved from
# the file the app ships, refused when the file doesn't know it, and never
# sent anywhere.
class PlaceTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a town the gazetteer knows resolves to its coordinates and country" do
    place = @user.places.create!(name: "tulsa")

    assert_equal "Tulsa", place.name
    assert_equal "Tulsa, United States", place.qualified_name
    assert_in_delta 36.12, place.latitude.to_f, 0.01
    assert_equal Place::DEFAULT_RADIUS_MI, place.radius_mi
    assert_equal Place::DEFAULT_LEAD_DAYS, place.lead_days
    assert place.alerts?
  end

  test "a country after the comma picks the right one" do
    assert_equal "Portugal", @user.places.create!(name: "Lisbon, Portugal").country
  end

  test "a name the map doesn't know is refused, not guessed" do
    place = @user.places.new(name: "The A-frame on Route 9")

    assert_not place.valid?
    assert_match(/isn't a town the map knows/, place.errors[:name].sole)
  end

  test "within? is the radius, in miles" do
    place = @user.places.create!(name: "Tulsa", radius_mi: 25)

    assert place.within?(36.15, -95.99)
    assert_not place.within?(35.47, -97.52)
  end

  test "the knobs are bounded" do
    assert_not @user.places.new(name: "Tulsa", radius_mi: 1000).valid?
    assert_not @user.places.new(name: "Tulsa", lead_days: 0).valid?
  end
end
