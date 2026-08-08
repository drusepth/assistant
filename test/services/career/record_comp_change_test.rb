require "test_helper"

# The comp timeline's granted-data rung (D30): a rate change between two
# analyzed pay stubs lands as a Career-tagged Event automatically — pure
# code over extracted facts, no model call deciding anything.
class Career::RecordCompChangeTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a rate change against the previous stub lands one comp-change event with provenance" do
    stub_document("March stub", rate: "$19.00", pay_date: "2026-03-15")
    current = stub_document("April stub", rate: "21", pay_date: "2026-04-15")

    event = nil
    assert_difference "Event.count", 1 do
      event = Career::RecordCompChange.new(current).call
    end

    assert_equal "Comp change: $19.00 → $21.00/hr", event.title
    assert event.all_day
    assert_equal Date.new(2026, 4, 15), event.starts_at.to_date
    assert_equal [ sections(:career) ], event.sections.to_a
    assert_includes event.description, "April stub"
  end

  test "recording twice logs once" do
    stub_document("March stub", rate: "19", pay_date: "2026-03-15")
    current = stub_document("April stub", rate: "21", pay_date: "2026-04-15")

    Career::RecordCompChange.new(current).call
    assert_no_difference "Event.count" do
      assert_nil Career::RecordCompChange.new(current).call
    end
  end

  test "a first stub logs nothing — a level is not a change" do
    current = stub_document("First stub", rate: "19", pay_date: "2026-03-15")

    assert_no_difference("Event.count") { Career::RecordCompChange.new(current).call }
  end

  test "an unchanged rate logs nothing" do
    stub_document("March stub", rate: "19.00", pay_date: "2026-03-15")
    current = stub_document("April stub", rate: "$19", pay_date: "2026-04-15")

    assert_no_difference("Event.count") { Career::RecordCompChange.new(current).call }
  end

  test "stubs from different employers never compare" do
    stub_document("Old job", rate: "19", pay_date: "2026-03-15", employer: "Acme")
    current = stub_document("New job", rate: "25", pay_date: "2026-04-15", employer: "Bravo")

    assert_no_difference("Event.count") { Career::RecordCompChange.new(current).call }
  end

  test "salaried stubs compare per-period gross when the periods match" do
    stub_document("March stub", gross: "$2,900.00", pay_date: "2026-03-15",
      period_start: "2026-03-01", period_end: "2026-03-14")
    current = stub_document("April stub", gross: "$3,100.00", pay_date: "2026-04-15",
      period_start: "2026-04-01", period_end: "2026-04-14")

    event = Career::RecordCompChange.new(current).call
    assert_equal "Comp change: gross $2,900.00 → $3,100.00 per pay period", event.title
  end

  test "a gross change across different period lengths is a calendar artifact, not a raise" do
    stub_document("Weekly stub", gross: "1450", pay_date: "2026-03-08",
      period_start: "2026-03-01", period_end: "2026-03-07")
    current = stub_document("Biweekly stub", gross: "2900", pay_date: "2026-04-15",
      period_start: "2026-04-01", period_end: "2026-04-14")

    assert_no_difference("Event.count") { Career::RecordCompChange.new(current).call }
  end

  test "another member's stubs are not this user's timeline" do
    other = users(:two).documents.create!(title: "Bob's stub",
      extracted_facts: { "pay_stub" => { "rate" => "15", "pay_date" => "2026-03-15" } })
    assert Career::PayStub.for(other)
    current = stub_document("My stub", rate: "21", pay_date: "2026-04-15")

    assert_no_difference("Event.count") { Career::RecordCompChange.new(current).call }
  end

  private
    def stub_document(title, **facts)
      @user.documents.create!(
        title: title,
        extracted_facts: { "pay_stub" => facts.transform_keys(&:to_s) }
      )
    end
end
