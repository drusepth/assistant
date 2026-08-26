require "test_helper"

# What the rail hands its tooltips. The rules under test: a row is labelled
# for a screen reader even when the rail is collapsed and its text is gone,
# a subsection is named by the name that reads unambiguously off its own
# page, and a row with nothing behind it hands over nothing to say.
class NavigationHelperTest < ActionView::TestCase
  include NavigationHelper
  include IconsHelper
  include SectionsHelper

  setup do
    Current.session = users(:one).sessions.create!
    travel_to Time.zone.local(2026, 6, 15, 9, 0)
  end

  teardown { Current.session = nil }

  test "a row carries its state, not a description of itself" do
    users(:one).tasks.create!(title: "Late one", due_on: 1.day.ago)
    users(:one).tasks.create!(title: "Someday")

    html = nav_link_to("Tasks", tasks_path, :check_circle)

    assert_includes html, %(data-tooltip-title-value="Tasks")
    assert_includes html, %(data-tooltip-detail-value="2 open · 1 unscheduled")
    assert_includes html, %(data-tooltip-badge-value="Overdue")
  end

  test "a row with nothing behind it hands over nothing to say" do
    html = nav_link_to("Notes", notes_path, :note)

    assert_includes html, %(data-tooltip-title-value="Notes")
    assert_no_match(/data-tooltip-detail-value/, html)
    assert_no_match(/data-tooltip-badge-value/, html)
  end

  test "every row is labelled for the collapsed rail, where its text is hidden" do
    assert_includes nav_link_to("Photos", photos_path, :photo), %(aria-label="Photos")
    assert_includes section_nav_link(sections(:career)), %(aria-label="Career")
  end

  test "a subsection is named by its qualified name, and still reads as itself" do
    html = section_nav_link(sections(:budget))

    assert_includes html, %(aria-label="Money · Budget")
    assert_includes html, %(data-tooltip-title-value="Money · Budget")
    assert_includes html, %(<span class="nav-label">Budget</span>)
  end

  test "one signals object serves the whole rail" do
    assert_same nav_signals, nav_signals
  end
end
