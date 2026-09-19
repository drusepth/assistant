require "test_helper"

# A happening is a candidate, not an Event (D-listing-feeds): it reaches
# the calendar or the board only by the one path a click takes.
class HappeningTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @place = @user.places.create!(name: "Tulsa")
    @source = @place.listing_sources.create!(url: "https://library.example/cal.ics", title: "Library")
    @happening = @source.happenings.create!(
      uid: "walk", title: "Fall bird walk", starts_at: 3.days.from_now.change(hour: 9),
      ends_at: 3.days.from_now.change(hour: 11), location: "Lakeside Park", url: "https://library.example/walk",
      description: "Bring binoculars."
    )
  end

  test "adding to the calendar makes one event, tagged Hobbies, linked back, and never twice" do
    event = @happening.add_to_calendar!

    assert_equal "Fall bird walk", event.title
    assert_equal "Lakeside Park", event.location
    assert_equal @happening.starts_at, event.starts_at
    assert_match "Bring binoculars.", event.description
    assert_match "Link: https://library.example/walk", event.description
    assert_equal [ "hobbies" ], event.sections.map(&:slug)
    assert_equal event, @happening.reload.event
    assert_same_elements [ event ], [ @happening.add_to_calendar! ]
    assert_equal 1, @user.events.count
  end

  test "making a task lands it on the board's Later pile with the link" do
    task = @happening.make_task!

    assert_equal "Look into: Fall bird walk", task.title
    assert_match "Link: https://library.example/walk", task.notes
    assert_equal "later", task.bucket
    assert_equal task, @happening.reload.task
  end

  test "the river's scopes: upcoming, in range, visible, live" do
    past = @source.happenings.create!(uid: "past", title: "Was", starts_at: 2.days.ago)
    hidden = @source.happenings.create!(uid: "hid", title: "Hid", starts_at: 2.days.from_now, hidden_at: Time.current)
    far = @source.happenings.create!(uid: "far", title: "Far", starts_at: 2.days.from_now, out_of_range: true)
    gone = @source.happenings.create!(uid: "gone", title: "Gone", starts_at: 2.days.from_now, withdrawn_at: Time.current)

    rows = Radar::River.new(@user).items

    assert_equal [ @happening ], rows
    assert_equal [ hidden ], Radar::River.new(@user, show: "hidden").items
    assert_equal [ far ], Radar::River.new(@user, show: "out_of_range").items
    assert_not_includes Happening.upcoming, past
    assert_not_includes Happening.live, gone
  end

  test "another member's places are not your river" do
    theirs = users(:two).places.create!(name: "Austin")
    theirs.listing_sources.create!(url: "https://x.example/cal.ics")
      .happenings.create!(uid: "t", title: "Bob's thing", starts_at: 2.days.from_now)

    assert_equal [ @happening ], Radar::River.new(@user).items
  end

  private
    def assert_same_elements(expected, actual)
      assert_equal expected.sort_by(&:id), actual.sort_by(&:id)
    end
end
