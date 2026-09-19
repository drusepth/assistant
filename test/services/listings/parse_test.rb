require "test_helper"

# What a listing parser makes of a stranger's calendar (D-listing-feeds):
# structured data read as data, text stripped to text, links refused unless
# http(s), and a recurring series named so it can be judged once.
class Listings::ParseTest < ActiveSupport::TestCase
  def ics(body)
    "BEGIN:VCALENDAR\nVERSION:2.0\n#{body}END:VCALENDAR\n"
  end

  test "an iCalendar event keeps its uid, link and coordinates" do
    items = Listings::Parse::Ics.call(ics(<<~ICS))
      BEGIN:VEVENT
      UID:walk-1@lib
      SUMMARY:Fall bird walk
      DESCRIPTION:Meet at the <b>north</b> lot.
      LOCATION:Lakeside Park
      DTSTART:20261003T140000Z
      DTEND:20261003T160000Z
      GEO:36.15;-95.99
      URL:https://library.example/walk
      END:VEVENT
    ICS

    item = items.sole
    assert_equal "walk-1@lib", item.uid
    assert_equal "walk-1@lib", item.series_uid
    assert_equal "Fall bird walk", item.title
    assert_equal "Meet at the north lot.", item.description, "markup is stripped at parse time"
    assert_equal "Lakeside Park", item.location
    assert_equal "https://library.example/walk", item.url
    assert_in_delta 36.15, item.latitude
    assert_in_delta(-95.99, item.longitude)
    assert_equal Time.utc(2026, 10, 3, 16), item.ends_at
    assert_not item.all_day
  end

  test "a recurring rule yields one row per occurrence sharing the master's series" do
    items = Listings::Parse::Ics.call(ics(<<~ICS))
      BEGIN:VEVENT
      UID:tuesday@club
      SUMMARY:Tuesday walk
      DTSTART:#{1.day.from_now.utc.strftime("%Y%m%dT180000Z")}
      RRULE:FREQ=WEEKLY;COUNT=3
      END:VEVENT
    ICS

    assert_equal 3, items.size
    assert_equal [ "tuesday@club" ], items.map(&:series_uid).uniq
    assert_equal 3, items.map(&:uid).uniq.size, "each occurrence is its own row"
    assert items.all? { |item| item.uid.start_with?("tuesday@club/") }
  end

  test "a javascript link and a cancelled event never reach a row" do
    items = Listings::Parse::Ics.call(ics(<<~ICS))
      BEGIN:VEVENT
      UID:bad
      SUMMARY:Click me
      DTSTART:20261003T140000Z
      URL:javascript:alert(1)
      END:VEVENT
      BEGIN:VEVENT
      UID:gone
      SUMMARY:Cancelled show
      STATUS:CANCELLED
      DTSTART:20261004T140000Z
      END:VEVENT
    ICS

    assert_equal [ "Click me" ], items.map(&:title)
    assert_nil items.sole.url
  end

  test "something that is not a calendar is nil, not an empty list" do
    assert_nil Listings::Parse::Ics.call("<html><body>hello</body></html>")
    assert_nil Listings::Parse::Schema.call("<html><body>hello</body></html>")
  end

  test "schema.org Event blocks on a page become rows, with venue and coordinates" do
    html = <<~HTML
      <html><head><script type="application/ld+json">
      [{"@context":"https://schema.org","@type":"MusicEvent","name":"Jazz night <em>live</em>",
        "startDate":"2026-10-05T20:00:00-05:00","endDate":"2026-10-05T23:00:00-05:00",
        "url":"https://venue.example/jazz","description":"Quartet.",
        "location":{"@type":"Place","name":"Cain's Ballroom",
          "address":{"@type":"PostalAddress","streetAddress":"423 N Main","addressLocality":"Tulsa"},
          "geo":{"@type":"GeoCoordinates","latitude":36.16,"longitude":-95.99}}},
       {"@type":"Event","name":"Called off","startDate":"2026-10-06","eventStatus":"https://schema.org/EventCancelled"},
       {"@type":"Event","name":"Undated","url":"https://venue.example/x"},
       {"@type":"Event","name":"Fair","startDate":"2026-10-07","location":{"@type":"VirtualLocation","url":"https://zoom.example"}}]
      </script></head></html>
    HTML

    items = Listings::Parse::Schema.call(html)

    assert_equal [ "Jazz night live", "Fair" ], items.map(&:title)
    jazz = items.first
    assert_equal "https://venue.example/jazz", jazz.uid, "the link is the id when the publisher gives no @id"
    assert_equal "Cain's Ballroom, 423 N Main, Tulsa", jazz.location
    assert_in_delta 36.16, jazz.latitude
    assert_equal Time.new(2026, 10, 5, 20, 0, 0, "-05:00"), jazz.starts_at
    assert_equal 3.hours, jazz.ends_at - jazz.starts_at
    fair = items.last
    assert fair.all_day, "a date-only start is an all-day event"
    assert_equal "Online", fair.location
    assert_nil fair.latitude
  end

  test "a @graph and an EventSeries's subEvents are walked" do
    html = <<~HTML
      <script type="application/ld+json">{"@context":"https://schema.org","@graph":[
        {"@type":"Organization","name":"The Venue"},
        {"@type":"EventSeries","name":"Open mic","startDate":"2026-10-01","subEvent":[
          {"@type":"Event","@id":"#om1","name":"Open mic — October","startDate":"2026-10-01T19:00:00Z"},
          {"@type":"Event","@id":"#om2","name":"Open mic — November","startDate":"2026-11-05T19:00:00Z"}]}]}</script>
    HTML

    items = Listings::Parse::Schema.call(html)

    assert_equal [ "Open mic", "Open mic — October", "Open mic — November" ], items.map(&:title)
    assert_equal [ "#om1", "#om2" ], items.last(2).map(&:uid)
  end

  test "a page with structured data but no events is an empty list, and a broken block is skipped" do
    html = <<~HTML
      <script type="application/ld+json">{not json</script>
      <script type="application/ld+json">{"@type":"Organization","name":"Nobody"}</script>
    HTML

    assert_nil Listings::Parse::Schema.call(html), "no events at all means this page is not a source"
  end
end
