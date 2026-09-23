require "test_helper"

class PetVaccinationTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user)
  end

  def dose(**attrs)
    @rex.pet_vaccinations.new({ user: @user, vaccine_key: "rabies", given_on: 1.month.ago.to_date }.merge(attrs))
  end

  test "a picked catalog vaccine names itself, and a duration derives the good-until date" do
    rabies = dose(duration_months: 36)
    assert rabies.save
    assert_equal "Rabies", rabies.name
    assert_equal 1.month.ago.to_date + 36.months, rabies.due_on
  end

  test "the certificate's date stands when no duration is picked" do
    rabies = dose(due_on: 1.year.from_now.to_date)
    assert rabies.save
    assert_equal 1.year.from_now.to_date, rabies.due_on
    assert_nil rabies.duration_months
  end

  test "no duration and no date is a real answer — the app never assumes one" do
    rabies = dose
    assert rabies.save
    assert_nil rabies.due_on
  end

  test "a dose in the future is an appointment, not a dose" do
    assert_not dose(given_on: 1.week.from_now.to_date).valid?
  end

  test "good-until must come after the date given" do
    assert_not dose(due_on: 2.months.ago.to_date).valid?
  end

  test "a catalog key must be one for her species; free text needs a name" do
    assert_not dose(vaccine_key: "fvrcp").valid?, "a dog has no FVRCP"
    assert_not dose(vaccine_key: nil, name: "").valid?
    assert dose(vaccine_key: nil, name: "Leishmaniasis").valid?
  end

  test "the kind is a closed set" do
    assert dose(kind: "titer").valid?
    assert dose(kind: "exemption").valid?
    assert_not dose(kind: "vibes").valid?
  end

  test "a listed vaccine groups by key; a typed one by its folded name" do
    assert_equal "rabies", dose.group_key
    assert_equal dose(vaccine_key: nil, name: "  Leish  Vaccine ").group_key,
      dose(vaccine_key: nil, name: "leish vaccine").group_key
  end

  test "visible exactly when the pet is" do
    dose.save!
    assert_equal 1, PetVaccination.visible_to(@user).count
    assert_equal 0, PetVaccination.visible_to(users(:two)).count

    @user.granted_access_grants.create!(grantee: users(:two), subject: @rex)
    assert_equal 1, PetVaccination.visible_to(users(:two)).count
  end

  test "the doses go with the pet, and outlive whoever logged them" do
    logged = dose(user: users(:two))
    logged.save!
    users(:two).destroy
    assert_nil logged.reload.user_id

    assert_difference -> { PetVaccination.count }, -1 do
      @rex.destroy
    end
  end

  test "the record leaves with its owner in the export" do
    dose(tag_number: "R-2291").save!
    names = []
    rows = nil
    Zip::File.open_buffer(Users::Export.new(@user).call) do |archive|
      names = archive.map(&:name)
      rows = archive.find_entry("pet_vaccinations.jsonl")&.get_input_stream&.read
    end
    assert_includes names, "pet_vaccinations.jsonl"
    assert_match "R-2291", rows
  end
end
