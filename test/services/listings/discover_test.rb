require "test_helper"

# Paste anything, get a listing source (D-listing-feeds): a calendar as-is,
# the page's own calendar link, the event data on the page, or the
# conventional paths — and an honest refusal otherwise.
class Listings::DiscoverTest < ActiveSupport::TestCase
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  ICS = "BEGIN:VCALENDAR\nX-WR-CALNAME:Library events\nBEGIN:VEVENT\nUID:1\nSUMMARY:Story time\nDTSTART:20261003T140000Z\nEND:VEVENT\nEND:VCALENDAR\n".freeze

  setup { Web::Fetch.resolver = PUBLIC_DNS }
  teardown { Web::Fetch.resolver = Resolv }

  test "a calendar link is a source as-is, named by the calendar" do
    stub_request(:get, "https://library.example/cal.ics").to_return(body: ICS, headers: { "Content-Type" => "text/calendar" })

    found = Listings::Discover.call("https://library.example/cal.ics")

    assert_equal "ics", found.kind
    assert_equal "Library events", found.title
    assert_equal 1, found.items.size
  end

  test "webcal:// is https:// wearing a hat" do
    stub_request(:get, "https://library.example/cal.ics").to_return(body: ICS)

    assert_equal "https://library.example/cal.ics", Listings::Discover.call("webcal://library.example/cal.ics").url
  end

  test "a Meetup group's address becomes its calendar export" do
    stub_request(:get, "https://www.meetup.com/tulsa-birders/events/ical/").to_return(body: ICS)

    found = Listings::Discover.call("https://www.meetup.com/tulsa-birders/")

    assert_equal "https://www.meetup.com/tulsa-birders/events/ical/", found.url
    assert_equal "ics", found.kind
  end

  test "a page pointing at its own calendar wins as ics" do
    stub_request(:get, "https://city.example/events").to_return(
      body: %(<html><head><link rel="alternate" type="text/calendar" href="/events.ics"></head></html>),
      headers: { "Content-Type" => "text/html" })
    stub_request(:get, "https://city.example/events.ics").to_return(body: ICS)

    found = Listings::Discover.call("https://city.example/events")

    assert_equal "https://city.example/events.ics", found.url
    assert_equal "ics", found.kind
  end

  test "a page carrying event data is a page source" do
    stub_request(:get, "https://venue.example/shows").to_return(
      body: %(<html><head><title>The Venue — Shows</title><script type="application/ld+json">{"@type":"Event","name":"Jazz","startDate":"2026-10-05T20:00:00Z"}</script></head></html>),
      headers: { "Content-Type" => "text/html" })

    found = Listings::Discover.call("venue.example/shows")

    assert_equal "page", found.kind
    assert_equal "The Venue — Shows", found.title
    assert_equal [ "Jazz" ], found.items.map(&:title)
  end

  test "the conventional paths are tried, and a page with nothing is refused honestly" do
    stub_request(:get, "https://plain.example/").to_return(body: "<html><body>Welcome</body></html>", headers: { "Content-Type" => "text/html" })
    stub_request(:get, %r{https://plain\.example/.+}).to_return(status: 404)

    error = assert_raises(Listings::Discover::Error) { Listings::Discover.call("https://plain.example/") }

    assert_match(/No calendar found/, error.message)
    assert_requested :get, "https://plain.example/calendar.ics"
  end

  test "a private address is refused before any fetch" do
    Web::Fetch.resolver = Class.new { def getaddresses(_host) = [ "10.0.0.5" ] }.new

    error = assert_raises(Listings::Discover::Error) { Listings::Discover.call("https://intranet.example/cal.ics") }

    assert_match(/private/, error.message)
  end
end
