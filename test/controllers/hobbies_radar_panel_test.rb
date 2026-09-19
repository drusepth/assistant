require "test_helper"

# The Near-you card on the Hobbies hub (D-event-radar): a doorway with no
# places, a card once there are, honest about a missing model. Its own file
# rather than an edit to the hub's test (D37).
class HobbiesRadarPanelTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "with no places the hub carries a one-line doorway, not a card" do
    get section_path("hobbies")

    assert_select "[data-hobby-radar-doorway]"
    assert_select "[data-hobby-radar]", false
    assert_match CGI.escapeHTML(places_path), response.body
  end

  test "with places and no model the card lists everything on next, date-first" do
    users(:one).household.model_profile.update!(api_key: "")
    place = users(:one).places.create!(name: "Tulsa")
    source = place.listing_sources.create!(url: "https://library.example/cal.ics", title: "Library")
    source.happenings.create!(uid: "walk", title: "Fall bird walk", starts_at: 3.days.from_now)
    source.happenings.create!(uid: "past", title: "Already happened", starts_at: 3.days.ago)

    get section_path("hobbies")

    assert_select "[data-hobby-radar]"
    assert_match "Fall bird walk", response.body
    assert_no_match "Already happened", response.body
    assert_match CGI.escapeHTML(happenings_path), response.body
  end

  test "with sources and no model the card says nothing is being matched" do
    users(:one).household.model_profile&.destroy
    place = users(:one).places.create!(name: "Tulsa")
    place.listing_sources.create!(url: "https://library.example/cal.ics")

    get section_path("hobbies")

    assert_match "No model is configured, so nothing here is matched", response.body
  end

  test "with places but no sources the card asks for one" do
    users(:one).places.create!(name: "Tulsa")

    get section_path("hobbies")

    assert_match "Follow one for Tulsa", response.body
  end
end
