require "test_helper"

# Folding a source's listings into happenings (D-listing-feeds): idempotent
# by uid, near by arithmetic when a row says where it is, withdrawn when
# the source stops listing it, pruned once it is long past.
class Listings::RefreshTest < ActiveJob::TestCase
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  setup do
    Web::Fetch.resolver = PUBLIC_DNS
    @user = users(:one)
    @place = @user.places.create!(name: "Tulsa", radius_mi: 25)
    @source = @place.listing_sources.create!(url: "https://library.example/cal.ics", kind: "ics")
  end

  teardown { Web::Fetch.resolver = Resolv }

  def stub_calendar(*events, headers: {})
    body = "BEGIN:VCALENDAR\n#{events.join}END:VCALENDAR\n"
    stub_request(:get, @source.url).to_return(body: body, headers: { "Content-Type" => "text/calendar" }.merge(headers))
  end

  def vevent(uid:, title:, at: 3.days.from_now, geo: nil, extra: "")
    <<~ICS
      BEGIN:VEVENT
      UID:#{uid}
      SUMMARY:#{title}
      DTSTART:#{at.utc.strftime("%Y%m%dT%H%M00Z")}
      #{"GEO:#{geo}" if geo}
      #{extra}
      END:VEVENT
    ICS
  end

  test "a first fetch lands the rows and stamps the source" do
    stub_calendar(vevent(uid: "a", title: "Story time"), vevent(uid: "b", title: "Book sale"))

    result = Listings::Refresh.call(@source)

    assert result.ok?
    assert_equal 2, result.added
    assert_equal %w[ Book\ sale Story\ time ], @source.happenings.pluck(:title).sort
    assert @source.reload.last_fetched_at
    assert @source.last_item_at
  end

  test "re-fetching keeps the user's state and updates a changed title in place" do
    stub_calendar(vevent(uid: "a", title: "Story tiem"))
    Listings::Refresh.call(@source)
    row = @source.happenings.sole
    row.hide!

    stub_calendar(vevent(uid: "a", title: "Story time"))
    result = Listings::Refresh.call(@source)

    assert_equal 0, result.added
    assert_equal 1, result.updated
    assert_equal "Story time", row.reload.title
    assert row.hidden?, "hiding is the user's, not the publisher's"
  end

  test "a row with coordinates beyond the radius is kept but out of range" do
    stub_calendar(
      vevent(uid: "near", title: "Bird walk", geo: "36.15;-95.99"),
      vevent(uid: "far", title: "State fair", geo: "35.47;-97.52"),
      vevent(uid: "unplaced", title: "Book club")
    )

    Listings::Refresh.call(@source)

    near, far, unplaced = %w[ near far unplaced ].map { |uid| @source.happenings.find_by!(uid: uid) }
    assert_not near.out_of_range?
    assert_in_delta 4, near.distance_mi.to_f, 1.5
    assert far.out_of_range?, "Oklahoma City is not within 25 miles of Tulsa"
    assert_not unplaced.out_of_range?, "a row that doesn't say where it is is at its source's place"
    assert_nil unplaced.distance_mi
  end

  test "an upcoming row the source stopped listing is withdrawn, and comes back if re-listed" do
    stub_calendar(vevent(uid: "a", title: "Story time"), vevent(uid: "b", title: "Cancelled later"))
    Listings::Refresh.call(@source)

    stub_calendar(vevent(uid: "a", title: "Story time"))
    result = Listings::Refresh.call(@source)

    assert_equal 1, result.withdrawn
    assert @source.happenings.find_by!(uid: "b").withdrawn?
    assert_not @source.happenings.find_by!(uid: "a").withdrawn?

    stub_calendar(vevent(uid: "a", title: "Story time"), vevent(uid: "b", title: "Cancelled later"))
    Listings::Refresh.call(@source)

    assert_not @source.happenings.find_by!(uid: "b").withdrawn?
  end

  test "long-past rows are pruned unless the user kept them" do
    @source.happenings.create!(uid: "old", title: "Last spring", starts_at: 60.days.ago)
    @source.happenings.create!(uid: "kept", title: "Went to this", starts_at: 60.days.ago).add_to_calendar!
    @source.happenings.create!(uid: "recent", title: "Last week", starts_at: 8.days.ago)

    stub_calendar(vevent(uid: "new", title: "Next week"))
    Listings::Refresh.call(@source)

    assert_equal %w[ kept new recent ], @source.happenings.pluck(:uid).sort
  end

  test "a 304 is an answer, not a parse" do
    stub_calendar(vevent(uid: "a", title: "Story time"), headers: { "ETag" => "v1" })
    Listings::Refresh.call(@source)
    assert_equal "v1", @source.reload.etag

    stub_request(:get, @source.url).with(headers: { "If-None-Match" => "v1" }).to_return(status: 304)
    result = Listings::Refresh.call(@source)

    assert result.ok?
    assert_not result.changed?
    assert_equal 1, @source.happenings.count
  end

  test "a fetch failure lands on the source's row instead of raising" do
    stub_request(:get, @source.url).to_return(status: 503)

    result = Listings::Refresh.call(@source)

    assert_not result.ok?
    assert_equal 1, @source.reload.failure_count
    assert_match(/503/, @source.last_error)
    assert_equal ListingSource::REFRESH_EVERY * 2, @source.refresh_interval
  end

  test "a page source reads its event data" do
    @source.update!(kind: "page", url: "https://venue.example/shows")
    stub_request(:get, @source.url).to_return(
      body: %(<script type="application/ld+json">{"@type":"Event","name":"Jazz","startDate":"#{5.days.from_now.iso8601}"}</script>),
      headers: { "Content-Type" => "text/html" })

    result = Listings::Refresh.call(@source)

    assert_equal 1, result.added
    assert_equal "Jazz", @source.happenings.sole.title
  end

  test "the sweep enqueues only sources past their own interval" do
    fresh = @place.listing_sources.create!(url: "https://a.example/cal.ics", last_fetched_at: 1.hour.ago)
    stale = @place.listing_sources.create!(url: "https://b.example/cal.ics", last_fetched_at: 7.hours.ago)

    assert_enqueued_with(job: RefreshListingSourceJob, args: [ stale ]) { RefreshListingsJob.refresh_due }
    assert_enqueued_jobs 2, only: RefreshListingSourceJob # the never-fetched @source, and stale
    assert_not fresh.due_for_refresh?
  end
end
