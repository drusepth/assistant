require "test_helper"

class Pets::VaccineStatusTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user)
  end

  def log(key: "rabies", name: nil, given: 1.year.ago.to_date, due: nil, **attrs)
    @rex.pet_vaccinations.create!(user: @user, vaccine_key: key, name: name, given_on: given, due_on: due, **attrs)
  end

  def status(viewer: @user) = Pets::VaccineStatus.new(@rex, viewer: viewer)
  def entry(group, viewer: @user) = status(viewer: viewer).entries.find { |e| e.group_key == group }

  test "each vaccine runs its own clock, and the latest dose decides" do
    log(given: 3.years.ago.to_date, due: 2.months.ago.to_date)
    log(given: 2.months.ago.to_date, due: 34.months.from_now.to_date)
    log(key: "bordetella", given: 6.months.ago.to_date, due: 10.days.from_now.to_date)
    log(key: "leptospirosis", given: 13.months.ago.to_date, due: 1.month.ago.to_date)
    log(key: "lyme", given: 1.month.ago.to_date)

    assert_equal :current, entry("rabies").state
    assert_equal 2, entry("rabies").doses.size
    assert_equal :due_soon, entry("bordetella").state
    assert_equal :overdue, entry("leptospirosis").state
    assert_equal :no_expiry, entry("lyme").state
    assert_equal %w[ leptospirosis bordetella rabies lyme ], status.entries.map(&:group_key),
      "what needs doing first, then by date, with no-expiry last"
  end

  test "a short interval gets a short lead, so a series booster isn't due the day it was given" do
    log(key: "dhpp", given: 2.days.ago.to_date, due: 19.days.from_now.to_date, series_dose: 1)
    assert_equal :current, entry("dhpp").state, "a third of three weeks is seven days"

    travel 13.days do
      assert_equal :due_soon, entry("dhpp").state
    end
  end

  test "a vaccination visit on the calendar books whatever is due, whoever booked it" do
    log(given: 3.years.ago.to_date, due: 5.days.from_now.to_date)
    @user.granted_access_grants.create!(grantee: users(:two), subject: @rex)
    users(:two).granted_access_grants.create!(grantee: @user, subject: @rex.section)
    visit = users(:two).events.create!(title: "Rex — shots", starts_at: 3.days.from_now, care_kind: "pet_vaccinations")
    visit.sections << @rex.section

    assert_equal :booked, entry("rabies").state
    assert_not entry("rabies").attention?
  end

  test "an event is a visit by its care kind, never by its title" do
    log(given: 3.years.ago.to_date, due: 5.days.from_now.to_date)
    guess = @user.events.create!(title: "Rex — rabies shot", starts_at: 3.days.from_now)
    guess.sections << @rex.section

    assert_equal :due_soon, entry("rabies").state
  end

  test "titers and exemptions count as coverage" do
    log(key: "dhpp", given: 1.month.ago.to_date, due: 3.years.from_now.to_date, kind: "titer")
    assert_equal :current, entry("dhpp").state
    assert entry("dhpp").latest.titer?
  end

  test "missing core vaccines are named for listed species only" do
    log
    assert_equal %w[ dhpp ], status.missing_core.map(&:key)

    iggy = create_pet(user: @user, name: "Iggy", species: "reptile")
    assert_empty Pets::VaccineStatus.new(iggy, viewer: @user).missing_core
  end

  test "reactions are collected for the warning line" do
    log(key: "leptospirosis", reaction: "Facial swelling")
    assert_equal [ "Facial swelling" ], status.reactions.map(&:reaction)
  end

  test "past vaccination visits with nothing logged against them are listed until they are" do
    visit = @user.events.create!(title: "Rex — vet", starts_at: 2.months.ago, care_kind: "pet_vaccinations")
    visit.sections << @rex.section
    assert_equal [ visit ], status.unlogged_visits

    log(given: 2.months.ago.to_date, event: visit)
    assert_empty status.unlogged_visits
  end

  test "a free-text vaccine groups with its own name" do
    log(key: nil, name: "Leishmaniasis", given: 2.years.ago.to_date, due: 1.year.ago.to_date)
    log(key: nil, name: "leishmaniasis", given: 1.month.ago.to_date, due: 11.months.from_now.to_date)

    assert_equal 1, status.entries.size
    assert_equal :current, status.entries.first.state
  end
end
