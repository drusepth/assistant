require "test_helper"

# The care radar over a pet (D-pet-care-radar) — a wellness exam is a checkup
# with a different noun, so this is the same machinery with a different
# subject.
class Pets::CareRadarTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user)
    @health = sections(:health)
  end

  def radar(pet = @rex, viewer: @user) = Health::CareRadar.new(pet, viewer: viewer)

  def vet_event(title, on, user: @user, sections: [ @health, @rex.section ])
    event = user.events.create!(title: title, starts_at: on)
    event.sections << sections
    event
  end

  test "the pet radar and the human radar never claim each other's events" do
    vet_event("Rex — dental", 2.months.ago)

    human = Health::CareRadar.new(@user).statuses.index_by { |status| status.kind.key }
    assert_equal :unknown, human["dental"].state,
      "the dog's teeth are not the owner's dental history"

    pet = radar.statuses.index_by { |status| status.kind.key }
    assert_equal :ok, pet["pet_dental"].state
  end

  test "a human's own health events still land on the human radar" do
    event = @user.events.create!(title: "Dental cleaning", starts_at: 2.months.ago)
    event.sections << @health

    human = Health::CareRadar.new(@user).statuses.index_by { |status| status.kind.key }
    assert_equal :ok, human["dental"].state
    assert_equal event, human["dental"].last_visit
  end

  test "a pet's care is whoever booked it, because there is only one dog" do
    # Grants are per-grantor, so the spouse shares their own Rex items back —
    # which is what the reciprocal button on a shared pet's page is for.
    users(:two).granted_access_grants.create!(grantee: @user, subject: @rex.section)
    booked = users(:two).events.create!(title: "Rex — vaccinations", starts_at: 3.days.from_now)
    booked.sections << @rex.section

    statuses = radar(viewer: @user).statuses.index_by { |status| status.kind.key }
    assert_equal :booked, statuses["pet_vaccinations"].state,
      "the spouse who books the vet books the dog's visit"
  end

  test "a person's radar is the opposite — a spouse's shared appointment is not your checkup" do
    users(:two).granted_access_grants.create!(grantee: @user, subject: sections(:health))
    theirs = users(:two).events.create!(title: "Dental cleaning", starts_at: 2.months.ago)
    theirs.sections << @health

    human = Health::CareRadar.new(@user).statuses.index_by { |status| status.kind.key }
    assert_equal :unknown, human["dental"].state
  end

  test "a pet's radar still reads through visible_to" do
    vet_event("Rex — vaccinations", 1.month.ago)

    statuses = radar(viewer: users(:two)).statuses.index_by { |status| status.kind.key }
    assert_equal :unknown, statuses["pet_vaccinations"].state, "no grant, no sight"
  end

  test "species decides the slate, and an unknown species claims only wellness" do
    assert_equal %w[ pet_wellness pet_vaccinations pet_dental pet_parasite pet_grooming pet_nails ],
      radar.kinds.map(&:key)

    cat = create_pet(name: "Luna", species: "cat")
    assert_equal %w[ pet_wellness pet_vaccinations pet_dental pet_parasite ], radar(cat).kinds.map(&:key)

    iggy = create_pet(name: "Iggy", species: "reptile")
    assert_equal %w[ pet_wellness ], radar(iggy).kinds.map(&:key),
      "we don't know an iguana's cadence, and saying so beats inventing one"
  end

  test "sub-month cadences are honoured rather than rounded to nothing" do
    vet_event("Rex — flea and worm treatment", 6.weeks.ago)
    vet_event("Rex — groom", 3.weeks.ago)

    statuses = radar.statuses.index_by { |status| status.kind.key }
    assert_equal :due, statuses["pet_parasite"].state, "a monthly treatment is due after a month"
    assert_equal :ok, statuses["pet_grooming"].state, "a six-week groom is not due at three weeks"
    assert_equal 6.weeks.ago.to_date + 1.month, statuses["pet_parasite"].due_on
  end

  test "grooming is upkeep, not care — no medical next-clicks, and its own noun" do
    grooming = radar.kinds.find { |kind| kind.key == "pet_grooming" }
    assert_not grooming.clinical?
    assert_equal "grooming", grooming.visit_noun
  end

  test "the specific kinds beat the generic wellness one" do
    assert_equal "pet_dental", radar.classify("Rex — dental").key
    assert_equal "pet_vaccinations", radar.classify("rabies booster").key
    assert_equal "pet_wellness", radar.classify("annual check").key
    assert_nil radar.classify("Rex to the park"), "an event it can't place doesn't count"
  end

  test "capture titles carry the pet's name, because the calendar is shared" do
    assert_equal "Rex — wellness exam", radar.kinds.first.appointment_title
  end
end
