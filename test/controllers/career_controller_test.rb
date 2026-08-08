require "test_helper"

class CareerControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "logging a win lands a career-tagged note wearing the Win prefix" do
    assert_difference "Note.count", 1 do
      post career_win_path, params: { text: "Caught the inventory error before the audit" }
    end

    note = users(:one).notes.order(:id).last
    assert note.title.start_with?("Win:")
    assert_equal "Caught the inventory error before the audit", note.body
    assert_equal [ sections(:career) ], note.sections.to_a
    assert_redirected_to section_path("career")
  end

  test "a blank win explains instead of blowing up" do
    assert_no_difference "Note.count" do
      post career_win_path, params: { text: "  " }
    end

    assert_equal "A win needs a line.", flash[:alert]
  end

  test "logging a comp change lands a career-tagged all-day event on the given date" do
    assert_difference "Event.count", 1 do
      post career_comp_change_path, params: { summary: "Raise: $19 → $21/hr", on: "2026-02-01" }
    end

    event = users(:one).events.order(:id).last
    assert_equal "Comp change: Raise: $19 → $21/hr", event.title
    assert event.all_day
    assert_equal Date.new(2026, 2, 1), event.starts_at.to_date
    assert_equal [ sections(:career) ], event.sections.to_a
  end

  test "a garbled date falls back to today" do
    post career_comp_change_path, params: { summary: "Promotion to shift lead", on: "soonish" }

    assert_equal Date.current, users(:one).events.order(:id).last.starts_at.to_date
  end

  test "a blank comp change explains instead of blowing up" do
    assert_no_difference "Event.count" do
      post career_comp_change_path, params: { summary: "" }
    end

    assert_match(/Describe the change/, flash[:alert])
  end
end
