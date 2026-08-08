require "test_helper"

class Health::CareRadarTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "classification is conservative and the specific kinds beat the generic checkup" do
    radar = Health::CareRadar.new(@user)
    assert_equal "dental", radar.classify("Dental checkup").key
    assert_equal "vision", radar.classify("Annual eye exam").key
    assert_equal "checkup", radar.classify("Annual physical").key
    assert_equal "checkup", radar.classify("Wellness visit").key
    assert_nil radar.classify("Therapy session")
    assert_nil radar.classify("Physical therapy")
    assert_nil radar.classify("Cardiology follow-up")
  end

  test "statuses cover every kind in display order, unknown without history" do
    statuses = Health::CareRadar.new(@user).statuses

    assert_equal %w[checkup dental vision], statuses.map { |status| status.kind.key }
    assert statuses.all? { |status| status.state == :unknown }
  end

  test "an upcoming visit is booked, a recent one is on track, an old one is due" do
    health_event "Dentist", 3.weeks.from_now
    health_event "Annual physical", 2.months.ago
    health_event "Eye exam", 30.months.ago

    by_key = Health::CareRadar.new(@user).statuses.index_by { |status| status.kind.key }

    assert_equal :booked, by_key["dental"].state
    assert_equal "Dentist", by_key["dental"].next_visit.title

    assert_equal :ok, by_key["checkup"].state
    assert_equal 2.months.ago.to_date >> 12, by_key["checkup"].due_on

    assert_equal :due, by_key["vision"].state
  end

  test "a booked appointment wins even when the last visit is overdue" do
    health_event "Dental cleaning", 14.months.ago
    health_event "Dentist", 2.weeks.from_now

    dental = Health::CareRadar.new(@user).statuses.find { |status| status.kind.key == "dental" }
    assert_equal :booked, dental.state
    assert_equal 14.months.ago.to_date, dental.last_visit_on
  end

  test "another user's shared event is not your checkup" do
    event = users(:two).events.create!(title: "Bob's physical", starts_at: 1.month.ago, all_day: true)
    event.sections << sections(:health)
    AccessGrant.create!(grantor: users(:two), grantee: @user, subject: event)

    checkup = Health::CareRadar.new(@user).statuses.find { |status| status.kind.key == "checkup" }
    assert_equal :unknown, checkup.state
  end

  test "untagged events don't count" do
    @user.events.create!(title: "Annual physical", starts_at: 1.month.ago, all_day: true)

    checkup = Health::CareRadar.new(@user).statuses.find { |status| status.kind.key == "checkup" }
    assert_equal :unknown, checkup.state
  end

  test "no seeded Health section means no statuses" do
    Section.find_by(slug: "health").destroy!

    assert_empty Health::CareRadar.new(@user).statuses
  end

  test "a muted kind disappears and an interval override changes the rhythm" do
    @user.care_settings.create!(kind_key: "vision", enabled: false)
    @user.care_settings.create!(kind_key: "dental", interval_months: 12)
    health_event "Dental cleaning", 8.months.ago

    statuses = Health::CareRadar.new(@user).statuses
    assert_equal %w[checkup dental], statuses.map { |status| status.kind.key }
    assert_equal :ok, statuses.last.state, "8 months ago is on track at a 12-month rhythm"
  end

  test "a custom kind classifies by its label and gets its own status" do
    @user.care_settings.create!(kind_key: "dermatology", label: "Dermatology", interval_months: 12)
    health_event "Dermatology follow-up", 14.months.ago

    radar = Health::CareRadar.new(@user)
    assert_equal "dermatology", radar.classify("Dermatology follow-up").key
    derm = radar.statuses.find { |status| status.kind.key == "dermatology" }
    assert_equal :due, derm.state
  end

  test "the user's care_kind beats the keywords, and 'none' excludes" do
    unmatched = health_event "Dr. Chen, 2pm", 2.months.ago
    unmatched.update!(care_kind: "checkup")
    refill = health_event "Annual physical paperwork", 1.month.ago
    refill.update!(care_kind: "none")

    checkup = Health::CareRadar.new(@user).statuses.find { |status| status.kind.key == "checkup" }
    assert_equal :ok, checkup.state
    assert_equal unmatched, checkup.last_visit, "the excluded event can't be the last visit"
  end

  test "a viewer sees another member's radar through the visibility wall only" do
    kid = users(:two)
    shared = kid.events.create!(title: "Dentist", starts_at: 2.weeks.from_now, all_day: true)
    shared.sections << sections(:health)
    AccessGrant.create!(grantor: kid, grantee: @user, subject: shared)
    unshared = kid.events.create!(title: "Eye exam", starts_at: 3.weeks.from_now, all_day: true)
    unshared.sections << sections(:health)

    statuses = Health::CareRadar.new(kid, viewer: @user).statuses.index_by { |status| status.kind.key }
    assert_equal :booked, statuses["dental"].state
    assert_equal :unknown, statuses["vision"].state, "the unshared eye exam stays invisible"
  end

  private
    def health_event(title, starts_at)
      event = @user.events.create!(title: title, starts_at: starts_at, all_day: true)
      event.sections << sections(:health)
      event
    end
end
