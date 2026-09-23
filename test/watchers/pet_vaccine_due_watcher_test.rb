require "test_helper"

class PetVaccineDueWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user)
  end

  def log(key, given:, due:)
    @rex.pet_vaccinations.create!(user: @user, vaccine_key: key, given_on: given, due_on: due)
  end

  def scan = Watcher::PetVaccineDue.new(@user).scan

  test "vaccines coming due together are one nudge naming them all" do
    log("rabies", given: 3.years.ago.to_date, due: 12.days.from_now.to_date)
    log("dhpp", given: 3.years.ago.to_date, due: 20.days.from_now.to_date)
    log("lyme", given: 1.month.ago.to_date, due: 11.months.from_now.to_date)

    nudges = scan
    assert_equal 1, nudges.size
    nudge = nudges.first
    assert_equal "Rex's Rabies and DHPP run out #{12.days.from_now.strftime("%B %-d")}", nudge.title
    assert_match "Nothing is booked yet.", nudge.body
    assert_no_match "Lyme", nudge.body
    assert_includes nudge.sections, @rex.section
    assert_equal "find_care", nudge.action.dig("tool", "slug"), "no vet on file: finding one comes first"
  end

  test "with a vet on file, accepting opens an appointment already marked as a vaccination visit" do
    @rex.update!(vet: @user.people.create!(name: "Dr. Okafor", relationship: "Vet"))
    log("rabies", given: 3.years.ago.to_date, due: 12.days.from_now.to_date)

    nudge = scan.sole
    assert_equal "Book the visit", nudge.accept_label
    assert_match "care_kind=pet_vaccinations", nudge.path_action
  end

  test "no good-until date, no nudge — and nothing far off" do
    @rex.pet_vaccinations.create!(user: @user, vaccine_key: "rabies", given_on: 3.years.ago.to_date)
    log("dhpp", given: 1.month.ago.to_date, due: 3.years.from_now.to_date)
    assert_empty scan
  end

  test "dismissing the heads-up doesn't silence the lapse" do
    log("rabies", given: 3.years.ago.to_date, due: 12.days.from_now.to_date)
    scan.sole.dismiss!
    assert_empty scan

    travel 15.days do
      assert_equal 1, scan.size, "overdue is its own notice"
    end
  end

  test "it retires when a newer dose is logged or the visit is booked" do
    log("rabies", given: 3.years.ago.to_date, due: 12.days.from_now.to_date)
    nudge = scan.sole
    watcher = Watcher::PetVaccineDue.new(@user)
    assert_not watcher.resolved?(nudge)

    visit = @user.events.create!(title: "Rex — shots", starts_at: 5.days.from_now, care_kind: "pet_vaccinations")
    visit.sections << @rex.section
    assert watcher.resolved?(nudge), "booked"

    visit.destroy
    log("rabies", given: Date.current, due: 3.years.from_now.to_date)
    assert Watcher::PetVaccineDue.new(@user).resolved?(nudge), "a new dose moved the date"
  end

  test "a pet who is gone is never scanned, and her nudges retire" do
    log("rabies", given: 3.years.ago.to_date, due: 12.days.from_now.to_date)
    nudge = scan.sole
    @rex.update!(died_on: Date.current)

    assert_empty scan
    assert Watcher::PetVaccineDue.new(@user).resolved?(nudge)
  end
end
