require "test_helper"

class PetWatchersTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user)
  end

  def care_event(title, on)
    event = @user.events.create!(title: title, starts_at: on)
    event.sections << @rex.section
    event
  end

  # ── Care cadence ──────────────────────────────────────────────────────

  test "a due kind with history nudges, and accepting opens find-care for a vet" do
    care_event("Rex — vaccinations", 14.months.ago)

    suggestions = Watcher::PetCareCadence.new(@user).scan
    nudge = suggestions.find { |suggestion| suggestion.title.include?("vaccinations") }

    assert nudge, "a year and a bit since the last shots, nothing booked"
    assert_match "Rex's last", nudge.body
    assert_equal "find_care", nudge.action.dig("tool", "slug")
    assert_match "veterinarian for a dog", nudge.action.dig("tool", "inputs", "specialty")
    assert_includes nudge.sections, @rex.section, "filed under her, so her lens page shows it"
  end

  test "no history means no nudge — the radar is the pull surface for unknowns" do
    assert_empty Watcher::PetCareCadence.new(@user).scan,
      "a guessed nudge costs trust (Q8)"
  end

  test "a booked visit silences the nudge" do
    care_event("Rex — vaccinations", 14.months.ago)
    care_event("Rex — vaccinations", 1.week.from_now)

    assert_empty Watcher::PetCareCadence.new(@user).scan
  end

  test "a groom accepts into a task, because a groomer is not a doctor" do
    care_event("Rex — groom", 12.weeks.ago)

    nudge = Watcher::PetCareCadence.new(@user).scan.find { |suggestion| suggestion.title.include?("groom") }
    assert nudge
    assert_nil nudge.action["tool"]
    assert_equal "Book Rex a groom", nudge.action.dig("task", "title")
  end

  test "a monthly rhythm can nudge again next month; a yearly one can't" do
    care_event("Rex — flea and worm treatment", 3.months.ago)
    care_event("Rex — vaccinations", 14.months.ago)

    first = Watcher::PetCareCadence.new(@user).scan
    assert_equal 2, first.size

    # Same scan again inside the same period: both deduped.
    assert_empty Watcher::PetCareCadence.new(@user).scan

    travel 40.days do
      again = Watcher::PetCareCadence.new(@user).scan.map { |suggestion| suggestion.watcher_slug }
      assert_equal 1, again.size, "the monthly treatment comes back; the vaccination stays quiet"
    end
  end

  test "a pet who is gone is never scanned" do
    care_event("Rex — vaccinations", 14.months.ago)
    @rex.update!(died_on: Date.current)

    assert_empty Watcher::PetCareCadence.new(@user).scan
  end

  # ── Food reorder ──────────────────────────────────────────────────────

  test "a bag about to run out nudges with the date it runs out" do
    food = @rex.pet_foods.create!(name: "Adult chicken", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12_000, started_on: 1.year.ago.to_date, opened_on: 38.days.ago.to_date)

    nudge = Watcher::PetFoodReorder.new(@user).scan.sole
    assert_equal "Reorder Rex's Adult chicken", nudge.title
    assert_match "runs out in about 2 days", nudge.body
    assert_equal food.runs_out_on.iso8601, nudge.action.dig("task", "due_on")
  end

  test "a reorder already on the calendar keeps the watcher quiet" do
    @rex.pet_foods.create!(name: "Adult chicken", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12_000, started_on: 1.year.ago.to_date, opened_on: 38.days.ago.to_date)
    @user.events.create!(title: "Reorder Rex's Adult chicken", starts_at: 2.days.from_now, all_day: true)

    assert_empty Watcher::PetFoodReorder.new(@user).scan,
      "being told twice about something you handled is how a watcher gets turned off"
  end

  test "a food whose numbers can't say when it runs out never nudges" do
    @rex.pet_foods.create!(name: "Tins", form: "wet", amount_per_day: 2, unit: "cans",
      package_amount: 24, started_on: 1.year.ago.to_date, opened_on: 1.year.ago.to_date)

    assert_empty Watcher::PetFoodReorder.new(@user).scan
  end

  test "a full bag is not news yet" do
    @rex.pet_foods.create!(name: "Adult chicken", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12_000, started_on: Date.current, opened_on: Date.current)

    assert_empty Watcher::PetFoodReorder.new(@user).scan
  end
end
