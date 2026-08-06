require "test_helper"

class Events::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    travel_to Time.zone.local(2026, 3, 2, 12) # fixture dates live around March 2026
  end

  test "shows the import form" do
    get new_events_import_path
    assert_response :success
    assert_match "Import calendar", response.body
  end

  test "imports an uploaded ICS and reports the count" do
    assert_difference("users(:one).events.count", 8) do
      post events_import_path, params: { file: fixture_file_upload("calendar.ics", "text/calendar") }
    end

    assert_redirected_to calendar_path
    assert_equal "Imported 8 events.", flash[:notice]
  end

  test "reports skipped duplicates" do
    users(:one).events.create!(title: "Rent due", starts_at: Time.zone.local(2026, 3, 20), all_day: true)

    post events_import_path, params: { file: fixture_file_upload("calendar.ics", "text/calendar") }
    assert_equal "Imported 7 events. Skipped 1 event already on your calendar.", flash[:notice]
  end

  test "rejects an unsupported file" do
    assert_no_difference("Event.count") do
      post events_import_path, params: { file: fixture_file_upload("sample.txt", "text/plain") }
    end

    assert_redirected_to new_events_import_path
    assert_match(/doesn't look like a calendar/, flash[:alert])
  end

  test "requires a file" do
    post events_import_path
    assert_redirected_to new_events_import_path
    assert_equal "Choose a file to import.", flash[:alert]
  end

  test "imported events belong to the signed-in user, not the household" do
    post events_import_path, params: { file: fixture_file_upload("generic_calendar.csv", "text/csv") }

    event = Event.find_by!(title: "Book club")
    assert_equal users(:one), event.user
  end
end
