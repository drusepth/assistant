require "test_helper"

# The river of what's on (D-event-radar) and its verbs: nothing lands
# without the click, and the click lands exactly one thing.
class HappeningsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @place = users(:one).places.create!(name: "Tulsa")
    @source = @place.listing_sources.create!(url: "https://library.example/cal.ics", title: "Library")
    @walk = @source.happenings.create!(uid: "walk", title: "Fall bird walk",
      starts_at: 3.days.from_now.change(hour: 9), location: "Lakeside Park", url: "https://library.example/walk")
    @sale = @source.happenings.create!(uid: "sale", title: "Book sale", starts_at: 10.days.from_now, all_day: true)
  end

  test "the river lists what's on by day, with the link out and the verbs" do
    get happenings_path

    assert_response :success
    assert_match "Fall bird walk", response.body
    assert_match "Book sale", response.body
    assert_match "Lakeside Park", response.body
    assert_select "a[href='https://library.example/walk'][rel~='noreferrer']"
    assert_select "form[action=?]", calendar_happening_path(@walk)
    assert_select "h2", text: happening_day_label(@walk.on)
  end

  test "it narrows to a place, and to a source" do
    other = users(:one).places.create!(name: "Austin")
    other.listing_sources.create!(url: "https://x.example/cal.ics").happenings.create!(uid: "a", title: "Austin thing", starts_at: 2.days.from_now)

    get happenings_path(place: @place.id)
    assert_match "Fall bird walk", response.body
    assert_no_match "Austin thing", response.body

    get happenings_path(place: @place.id, source: @source.id)
    assert_match "From Library only", response.body
  end

  test "Add to calendar makes the event once and the row says so" do
    post calendar_happening_path(@walk), as: :turbo_stream

    assert_response :success
    event = users(:one).events.find_by!(title: "Fall bird walk")
    assert_equal event, @walk.reload.event
    assert_match "on your calendar", response.body
    assert_match event_path(event), response.body

    post calendar_happening_path(@walk)
    assert_equal 1, users(:one).events.where(title: "Fall bird walk").count
  end

  test "Task makes a task; Hide moves the row to the hidden pile and Unhide brings it back" do
    post task_happening_path(@sale)
    assert users(:one).tasks.find_by(title: "Look into: Book sale")

    patch hide_happening_path(@walk), as: :turbo_stream
    assert @walk.reload.hidden?

    get happenings_path
    assert_no_match "Fall bird walk", response.body
    get happenings_path(show: "hidden")
    assert_match "Fall bird walk", response.body

    patch unhide_happening_path(@walk)
    assert_not @walk.reload.hidden?
  end

  test "another member's happening is not reachable" do
    theirs = users(:two).places.create!(name: "Austin").listing_sources.create!(url: "https://x.example/cal.ics")
      .happenings.create!(uid: "t", title: "Bob's thing", starts_at: 2.days.from_now)

    post calendar_happening_path(theirs)

    assert_response :not_found
    assert_empty users(:one).events
  end

  test "with no places the page says where to start" do
    users(:one).places.destroy_all

    get happenings_path

    assert_match "Add a place", response.body
  end

  private
    def happening_day_label(date)
      ApplicationController.helpers.happening_day_label(date)
    end
end
