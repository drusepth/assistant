require "test_helper"

class MedicationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "adding a medication files a note and a radar-excluded refill event" do
    post medications_path, params: { name: "Lisinopril 10mg", details: "one every morning", refill_on: 3.weeks.from_now.to_date.iso8601 }
    assert_redirected_to section_path("health")

    note = users(:one).notes.medications.sole
    assert_equal "Lisinopril 10mg", note.title
    assert_equal "one every morning", note.body
    assert_equal [ sections(:health) ], note.sections.to_a

    event = users(:one).events.find_by!(title: "Refill Lisinopril 10mg")
    assert event.all_day?
    assert_equal "none", event.care_kind, "a refill is never a visit"
    assert_equal [ sections(:health) ], event.sections.to_a
  end

  test "no refill date means no event, and a blank name is refused" do
    post medications_path, params: { name: "Metformin" }
    assert users(:one).notes.medications.exists?(title: "Metformin")
    assert_empty users(:one).events

    post medications_path, params: { name: "" }
    assert_equal 1, users(:one).notes.medications.count
  end
end
