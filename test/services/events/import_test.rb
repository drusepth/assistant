require "test_helper"

class Events::ImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  CHICAGO = ActiveSupport::TimeZone["America/Chicago"]

  setup do
    @user = users(:one)
    travel_to Time.zone.local(2026, 3, 2, 12) # fixture dates live around March 2026
  end

  def import(fixture)
    Events::Import.new(user: @user, file: file_fixture(fixture).open).call
  end

  test "imports an ICS file with zoned times, escapes, folding, and overflow details" do
    result = assert_difference("@user.events.count", 8) { import("calendar.ics") }

    assert_equal 8, result.imported
    assert_equal 0, result.skipped
    assert_nil result.error

    appt = @user.events.find_by!(title: "Cardiology appointment")
    assert_equal CHICAGO.local(2026, 3, 10, 9, 0), appt.starts_at
    assert_equal CHICAGO.local(2026, 3, 10, 9, 30), appt.ends_at
    assert_not appt.all_day?
    assert_equal "St. Mary's Hospital, Suite 200", appt.location
    assert_includes appt.description, "Bring insurance card.\nAsk about refill."
    assert_includes appt.description, "arrive fifteen minutes early"
    assert_includes appt.description, "Organizer: Dr. Rivera"
    assert_includes appt.description, "Link: https://stmarys.example.com/visit"
  end

  test "handles UTC times and DURATION" do
    import("calendar.ics")

    webinar = @user.events.find_by!(title: "Tax webinar")
    assert_equal Time.utc(2026, 3, 15, 17), webinar.starts_at
    assert_equal Time.utc(2026, 3, 15, 18), webinar.ends_at
  end

  test "handles all-day and multi-day events with exclusive DTEND" do
    import("calendar.ics")

    rent = @user.events.find_by!(title: "Rent due")
    assert rent.all_day?
    assert_equal Time.zone.local(2026, 3, 20), rent.starts_at
    assert_nil rent.ends_at

    trip = @user.events.find_by!(title: "Spring break trip")
    assert trip.all_day?
    assert_equal Time.zone.local(2026, 4, 1), trip.starts_at
    assert_equal Time.zone.local(2026, 4, 3), trip.ends_at
  end

  test "skips cancelled events" do
    import("calendar.ics")
    assert_nil @user.events.find_by(title: "Cancelled lunch")
  end

  test "expands recurring events honoring EXDATE and RECURRENCE-ID overrides" do
    import("calendar.ics")

    # Weekly Tuesdays, COUNT=4 (Mar 3, 10, 17, 24): the 10th is EXDATEd and
    # the 17th was moved to its own override event, leaving two instances.
    classes = @user.events.where(title: "Pottery class").order(:starts_at)
    assert_equal [ CHICAGO.local(2026, 3, 3, 18, 30), CHICAGO.local(2026, 3, 24, 18, 30) ], classes.pluck(:starts_at)
    assert_equal CHICAGO.local(2026, 3, 3, 19, 30), classes.first.ends_at
    assert_includes classes.first.description, "Repeats: weekly on Tuesday, 4 times"

    moved = @user.events.find_by!(title: "Pottery class (moved)")
    assert_equal CHICAGO.local(2026, 3, 18, 19, 0), moved.starts_at
  end

  test "keeps the first occurrence and the raw rule for exotic recurrences" do
    import("calendar.ics")

    standup = @user.events.find_by!(title: "Complicated standup")
    assert_equal CHICAGO.local(2026, 3, 6, 8, 0), standup.starts_at
    assert_includes standup.description, "Repeats: FREQ=HOURLY;COUNT=3"
  end

  test "bounds unbounded recurrences to the import window" do
    result = import("recurring_calendar.ics")

    # Monthly from Jan 15 2026, forever: the window runs a month back and a
    # year ahead of "today" (Mar 2 2026), so Feb 2026 through Feb 2027 land.
    assert_equal 13, result.imported
    reviews = @user.events.where(title: "Budget review").order(:starts_at)
    assert_equal CHICAGO.local(2026, 2, 15, 12), reviews.first.starts_at
    assert_equal CHICAGO.local(2027, 2, 15, 12), reviews.last.starts_at
    assert_includes reviews.first.description, "Repeats: monthly"
  end

  test "leaves imported events untagged and never enqueues categorize jobs" do
    assert_no_enqueued_jobs(only: CategorizeEventJob) { import("calendar.ics") }

    assert_empty @user.events.find_by!(title: "Rent due").sections
  end

  test "imports an Outlook CSV" do
    result = import("outlook_calendar.csv")
    assert_equal 2, result.imported

    dentist = @user.events.find_by!(title: "Dentist")
    assert_equal Time.zone.local(2026, 3, 12, 14, 0), dentist.starts_at
    assert_equal Time.zone.local(2026, 3, 12, 15, 0), dentist.ends_at
    assert_not dentist.all_day?
    assert_equal "Smile Dental", dentist.location
    assert_includes dentist.description, "Six month cleaning"
    assert_includes dentist.description, "Categories: Health"

    tax = @user.events.find_by!(title: "Property tax due")
    assert tax.all_day?
    assert_equal Time.zone.local(2026, 3, 31), tax.starts_at
    assert_nil tax.ends_at
  end

  test "imports any CSV with recognizable headers" do
    result = import("generic_calendar.csv")
    assert_equal 2, result.imported

    club = @user.events.find_by!(title: "Book club")
    assert_equal Time.zone.local(2026, 3, 18, 19, 0), club.starts_at
    assert_equal Time.zone.local(2026, 3, 18, 20, 30), club.ends_at
    assert_equal "Library", club.location
    assert_equal "Bring snacks", club.description

    marathon = @user.events.find_by!(title: "Marathon")
    assert marathon.all_day?
    assert_equal Time.zone.local(2026, 4, 12), marathon.starts_at
  end

  test "skips events already on the calendar by title and start time" do
    @user.events.create!(title: "Rent due", starts_at: Time.zone.local(2026, 3, 20), all_day: true, description: "keep me")

    result = import("calendar.ics")
    assert_equal 7, result.imported
    assert_equal 1, result.skipped
    assert_equal "keep me", @user.events.find_by!(title: "Rent due").description
  end

  test "importing the same file twice is idempotent" do
    import("calendar.ics")
    result = assert_no_difference("Event.count") { import("calendar.ics") }

    assert_equal 0, result.imported
    assert_equal 8, result.skipped
  end

  test "rejects files that are not calendars" do
    result = assert_no_difference("Event.count") { import("sample.txt") }

    assert_equal 0, result.imported
    assert_match(/doesn't look like a calendar/, result.error)
  end

  test "rejects an address book file" do
    result = assert_no_difference("Event.count") { import("contacts.vcf") }

    assert_match(/doesn't look like a calendar/, result.error)
  end
end
