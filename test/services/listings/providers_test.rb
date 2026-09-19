require "test_helper"

# The opt-in search (D-listing-feeds §8): a keyed provider queried by the
# place's point, off until the sentence on the switch is agreed to, and its
# category riding the description rather than deciding anything.
class Listings::ProvidersTest < ActionDispatch::IntegrationTest
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  setup do
    Web::Fetch.resolver = PUBLIC_DNS
    sign_in_as users(:one)
    @place = users(:one).places.create!(name: "Tulsa", radius_km: 40)
  end

  teardown { Web::Fetch.resolver = Resolv }

  def discovery(events, total_pages: 1)
    { _embedded: { events: events }, page: { totalPages: total_pages } }.to_json
  end

  def tm_event(id:, name:, at:, status: "onsale", lat: 36.16, lng: -95.99)
    { id: id, name: name, url: "https://www.ticketmaster.com/e/#{id}", info: "Doors at 7.",
      dates: { start: { dateTime: at.utc.iso8601 }, status: { code: status } },
      classifications: [ { segment: { name: "Music" }, genre: { name: "Jazz" } } ],
      _embedded: { venues: [ { name: "Cain's Ballroom", city: { name: "Tulsa" }, location: { latitude: lat.to_s, longitude: lng.to_s } } ] } }
  end

  test "turning a provider on needs the key and the tick, then searches the place's point" do
    post place_listing_sources_path(@place), params: { provider: "ticketmaster", credentials: { api_key: "k" } }
    assert_match(/Tick the box/, flash[:alert])
    assert_empty @place.listing_sources

    post place_listing_sources_path(@place), params: { provider: "ticketmaster", consent: "1", credentials: { api_key: "" } }
    assert_match(/can't be blank/, flash[:alert])

    assert_enqueued_with(job: RefreshListingSourceJob) do
      post place_listing_sources_path(@place), params: { provider: "ticketmaster", consent: "1", credentials: { api_key: "k" } }
    end
    source = @place.listing_sources.sole
    assert source.provider?
    assert_equal "k", source.credentials["api_key"]
    assert source.due_for_refresh?

    show = 8.days.from_now.change(hour: 20)
    stub_request(:get, %r{app\.ticketmaster\.com/discovery/v2/events\.json\?.*latlong=36\.12,-95\.93.*radius=40})
      .to_return(body: discovery([ tm_event(id: "a", name: "Jazz night", at: show),
                                   tm_event(id: "b", name: "Cancelled", at: show, status: "cancelled"),
                                   tm_event(id: "c", name: "Far away", at: show, lat: 35.47, lng: -97.52) ]),
                 headers: { "Content-Type" => "application/json" })

    result = Listings::Refresh.call(source)

    assert result.ok?
    assert_equal 2, result.added
    jazz = source.happenings.find_by!(uid: "tm:a")
    assert_equal "Cain's Ballroom, Tulsa", jazz.location
    assert_match "Ticketmaster: Music / Jazz", jazz.description, "the category is context, not a filter"
    assert_not jazz.out_of_range?
    assert source.happenings.find_by!(uid: "tm:c").out_of_range?, "the radius still applies to what comes back"
    assert_nil source.happenings.find_by(uid: "tm:b")
  end

  test "the place card carries the switch with its sentence, and says so once it is on" do
    get places_path
    assert_select "[data-providers]"
    assert_match "sends the place&#39;s coordinates", response.body

    @place.listing_sources.create!(url: ListingSource::PROVIDERS["ticketmaster"][:url], kind: "provider",
      provider: "ticketmaster", title: "Ticketmaster", credentials: { "api_key" => "k" })
    get places_path
    assert_match "Ticketmaster — on", response.body
  end

  test "a bad key lands on the row like any failure" do
    source = @place.listing_sources.create!(url: ListingSource::PROVIDERS["ticketmaster"][:url], kind: "provider",
      provider: "ticketmaster", credentials: { "api_key" => "bad" })
    stub_request(:get, %r{app\.ticketmaster\.com}).to_return(status: 401)

    result = Listings::Refresh.call(source)

    assert_not result.ok?
    assert_match(/401/, source.reload.last_error)
  end
end
