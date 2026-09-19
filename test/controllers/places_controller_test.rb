require "test_helper"

# Places and the calendars followed under them (D-place-subscriptions,
# D-listing-feeds): the paste box fetches now, everything else is a job, and
# nobody's places are anybody else's.
class PlacesControllerTest < ActionDispatch::IntegrationTest
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  ICS = "BEGIN:VCALENDAR\nX-WR-CALNAME:Library events\nBEGIN:VEVENT\nUID:1\nSUMMARY:Story time\nDTSTART:20261003T140000Z\nEND:VEVENT\nEND:VCALENDAR\n".freeze

  setup do
    Web::Fetch.resolver = PUBLIC_DNS
    sign_in_as users(:one)
  end

  teardown { Web::Fetch.resolver = Resolv }

  test "the empty page offers home from the household address, and never assumes it" do
    users(:one).household.update!(address: "123 Maple Street\nTulsa, OK 74103")

    get places_path

    assert_response :success
    assert_select "input[name='place[name]'][value=?]", "Tulsa"
    assert_match "town on your household address", response.body
    assert_empty users(:one).places, "offered, not added"
  end

  test "adding a place the map knows, and refusing one it doesn't" do
    post places_path, params: { place: { name: "Tulsa" } }
    assert_redirected_to places_path
    assert_equal "Tulsa", users(:one).places.sole.name

    post places_path, params: { place: { name: "Nowhere Particular" } }
    assert_redirected_to places_path
    assert_match(/isn't a town the map knows/, flash[:alert])
    assert_equal 1, users(:one).places.count
  end

  test "following a calendar fetches it now, names it, and checks it in a job" do
    place = users(:one).places.create!(name: "Tulsa")
    stub_request(:get, "https://library.example/cal.ics").to_return(body: ICS)

    assert_enqueued_with(job: RefreshListingSourceJob) do
      post place_listing_sources_path(place), params: { listing_source: { url: "https://library.example/cal.ics" } }
    end

    assert_redirected_to places_path
    source = place.listing_sources.sole
    assert_equal "Library events", source.title
    assert_equal "ics", source.kind
    assert_match "1 listing found", flash[:notice]
  end

  test "a page with no calendar is refused with the reason" do
    place = users(:one).places.create!(name: "Tulsa")
    stub_request(:get, "https://plain.example/").to_return(body: "<html>hi</html>", headers: { "Content-Type" => "text/html" })
    stub_request(:get, %r{https://plain\.example/.+}).to_return(status: 404)

    post place_listing_sources_path(place), params: { listing_source: { url: "https://plain.example/" } }

    assert_redirected_to places_path
    assert_match(/No calendar found/, flash[:alert])
    assert_empty place.listing_sources
  end

  test "the page shows each place's sources with their health, and the help card" do
    place = users(:one).places.create!(name: "Tulsa")
    place.listing_sources.create!(url: "https://a.example/cal.ics", title: "Library", last_fetched_at: 1.hour.ago)
    place.listing_sources.create!(url: "https://b.example/cal.ics", title: "Broken", last_error: "the site answered HTTP 503", failure_count: 2)

    get places_path

    assert_response :success
    assert_match "Library", response.body
    assert_match "failing — the site answered HTTP 503", response.body
    assert_match "Where calendars hide around Tulsa", response.body
    assert_select "a[href*='duckduckgo.com'][rel~='noreferrer']", minimum: 3
  end

  test "settings, and removing a place" do
    place = users(:one).places.create!(name: "Tulsa")

    patch place_path(place), params: { place: { radius_km: 80, lead_days: 30, alerts: "0" } }

    assert_redirected_to places_path
    place.reload
    assert_equal 80, place.radius_km
    assert_equal 30, place.lead_days
    assert_not place.alerts?

    delete place_path(place)

    assert_redirected_to places_path
    assert_empty users(:one).places.reload
  end

  test "another member's place and source are not reachable" do
    theirs = users(:two).places.create!(name: "Austin")
    source = theirs.listing_sources.create!(url: "https://x.example/cal.ics")

    patch place_path(theirs), params: { place: { radius_km: 80 } }
    assert_response :not_found
    delete listing_source_path(source)
    assert_response :not_found
    post place_listing_sources_path(theirs), params: { listing_source: { url: "https://x.example/cal.ics" } }
    assert_response :not_found
  end
end

class PlacesGroupsShelfTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  # Offered, never subscribed (D-radar-accounts): the groups on the linked
  # account are a shelf under each place, one tick each.
  test "a linked Meetup account's groups are offered under each place" do
    users(:one).linked_accounts.create!(provider: "meetup",
      credentials: { "calendar_url" => "webcal://www.meetup.com/ical/abc", "groups" => "tulsa-birders" })
    place = users(:one).places.create!(name: "Tulsa")

    get places_path

    assert_select "[data-your-groups]"
    assert_match "Tulsa birders", response.body
    assert_select "form[action=?] input[name='listing_source[url]'][value=?]", place_listing_sources_path(place),
      "https://www.meetup.com/tulsa-birders/events/ical/"
    assert_empty place.listing_sources, "nothing followed until the tick"
  end
end
