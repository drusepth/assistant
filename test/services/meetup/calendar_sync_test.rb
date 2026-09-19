require "test_helper"

# Your own Meetup calendar (D-radar-accounts): RSVPs are calendar sync,
# "maybe" is a happening you already judged, groups are offered.
class Meetup::CalendarSyncTest < ActiveJob::TestCase
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  setup do
    Web::Fetch.resolver = PUBLIC_DNS
    @user = users(:one)
    @account = @user.linked_accounts.create!(provider: "meetup",
      credentials: { "calendar_url" => "webcal://www.meetup.com/ical/abc123", "groups" => "tulsa-birders, okc-hikers" })
    @place = @user.places.create!(name: "Tulsa")
  end

  teardown { Web::Fetch.resolver = Resolv }

  def calendar
    going = 5.days.from_now.utc.strftime("%Y%m%dT180000Z")
    maybe = 9.days.from_now.utc.strftime("%Y%m%dT190000Z")
    <<~ICS
      BEGIN:VCALENDAR
      BEGIN:VEVENT
      UID:going@meetup
      SUMMARY:Bird walk at Oxley
      DTSTART:#{going}
      STATUS:CONFIRMED
      LOCATION:Oxley Nature Center
      GEO:36.22;-95.90
      URL:https://www.meetup.com/tulsa-birders/events/1/
      END:VEVENT
      BEGIN:VEVENT
      UID:maybe@meetup
      SUMMARY:Board game night
      DTSTART:#{maybe}
      STATUS:TENTATIVE
      GEO:36.15;-95.99
      URL:https://www.meetup.com/tulsa-games/events/2/
      END:VEVENT
      END:VCALENDAR
    ICS
  end

  test "RSVPs land on the calendar tagged Hobbies, maybes become saved happenings, and neither repeats" do
    stub_request(:get, "https://www.meetup.com/ical/abc123").to_return(body: calendar, headers: { "Content-Type" => "text/calendar" })

    result = Meetup::CalendarSync.new(@account).call

    assert_equal 1, result.imported
    assert_equal 1, result.saved
    event = @user.events.find_by!(title: "Bird walk at Oxley")
    assert_equal [ "hobbies" ], event.sections.map(&:slug)
    assert_equal "Oxley Nature Center", event.location

    saved = @place.happenings.find_by!(uid: "maybe@meetup")
    assert saved.provenance_saved?
    assert saved.matched_at, "never read by the model"
    assert_equal "Saved on Meetup", saved.source_name
    assert_not saved.listing_source.fetched?

    again = Meetup::CalendarSync.new(@account).call
    assert_equal 0, again.imported
    assert_equal 1, again.skipped
    assert_equal 1, @place.happenings.where(uid: "maybe@meetup").count
  end

  test "a maybe that vanishes from the export was un-saved" do
    stub_request(:get, "https://www.meetup.com/ical/abc123").to_return(body: calendar)
    Meetup::CalendarSync.new(@account).call

    stub_request(:get, "https://www.meetup.com/ical/abc123").to_return(body: "BEGIN:VCALENDAR\nEND:VCALENDAR\n")
    Meetup::CalendarSync.new(@account).call

    assert @place.happenings.find_by!(uid: "maybe@meetup").withdrawn?
  end

  test "a saved row is nudged by the watcher, and the model is never asked about it" do
    stub_request(:get, "https://www.meetup.com/ical/abc123").to_return(body: calendar)
    Meetup::CalendarSync.new(@account).call

    watcher = Watcher::EventRadar.new(@user)
    watcher.scan

    nudge = watcher.proposals.sole
    assert_match "Board game night", nudge.title
    assert_match "You saved this yourself.", nudge.body
    assert_empty Radar::Match.call(@user)
  end

  test "the groups are offered under a place, followed only by a tick" do
    groups = Radar::Groups.new(@user)

    assert_equal %w[ tulsa-birders okc-hikers ], groups.all.map(&:slug)
    assert_equal "https://www.meetup.com/tulsa-birders/events/ical/", groups.all.first.url
    assert_equal 2, groups.unfollowed_for(@place).size

    @place.listing_sources.create!(url: "https://www.meetup.com/tulsa-birders/events/ical/")
    assert_equal %w[ okc-hikers ], groups.unfollowed_for(@place).map(&:slug)

    @account.update!(disabled_scopes: [ "groups" ])
    assert_empty Radar::Groups.new(@user).all
  end

  test "with no place there is nowhere to put a maybe, and RSVPs still sync" do
    @place.destroy!
    stub_request(:get, "https://www.meetup.com/ical/abc123").to_return(body: calendar)

    result = Meetup::CalendarSync.new(@account).call

    assert_equal 1, result.imported
    assert_equal 0, result.saved
  end

  test "fails closed with the read scope off, and the job records a bad link" do
    @account.update!(disabled_scopes: [ "read" ])
    assert_raises(Meetup::CalendarSync::Error) { Meetup::CalendarSync.new(@account).call }

    @account.update!(disabled_scopes: [])
    stub_request(:get, "https://www.meetup.com/ical/abc123").to_return(status: 404)
    SyncLinkedAccountJob.perform_now(@account)

    assert_match(/404/, @account.reload.sync_error)
  end
end
