require "test_helper"

# D-person-picker: the type-to-find that replaced the address-book <select>.
class People::PickerTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "names that start with the query come first, then a later word, then anything else" do
    later = @user.people.create!(name: "Anna Lee")
    prefix = @user.people.create!(name: "Lee Park")
    inside = @user.people.create!(name: "Kaleen Ortiz")
    relation = @user.people.create!(name: "Pat", relationship: "Lee's brother")

    assert_equal [ prefix, later, inside, relation ], People::Picker.for_circle(@user).matches("lee")
  end

  test "caps the suggestions and ignores a blank query" do
    12.times { |i| @user.people.create!(name: "Sam #{i}") }
    picker = People::Picker.for_circle(@user)

    assert_equal People::Picker::LIMIT, picker.matches("sam").size
    assert_empty picker.matches("  ")
  end

  test "the circle picker leaves out who's already in it, and other members' contacts" do
    @user.people.create!(name: "Rosa In", keep_in_touch: true)
    out = @user.people.create!(name: "Rosa Out")
    users(:two).people.create!(name: "Rosa Theirs")

    assert_equal [ out ], People::Picker.for_circle(@user).matches("rosa")
  end

  test "the group picker leaves out current members" do
    group = People::Group.find_or_create!("Book club")
    @user.people.create!(name: "Rosa In").sections << group
    out = @user.people.create!(name: "Rosa Out")

    assert_equal [ out ], People::Picker.for_group(@user, group).matches("rosa")
  end

  test "treats LIKE wildcards in the query as text" do
    @user.people.create!(name: "Anyone")

    assert_empty People::Picker.for_circle(@user).matches("%")
  end

  test "resolve reuses an exact name, case-insensitively, instead of duplicating" do
    rosa = @user.people.create!(name: "Rosa")

    assert_no_difference "Person.count" do
      assert_equal rosa, People::Picker.for_circle(@user).resolve(name: " rosa ")
    end
  end

  test "resolve makes a new contact of the viewer's own for a new name" do
    person = People::Picker.for_circle(@user).resolve(name: "  New  Friend ")

    assert person.previously_new_record?
    assert_equal "New Friend", person.name
    assert_equal @user, person.user
  end

  test "resolve won't pick a person outside the pool" do
    theirs = users(:two).people.create!(name: "Unshared")

    assert_nil People::Picker.for_circle(@user).resolve(person_id: theirs.id)
  end

  test "suggestions come from plain facts, strongest first, each with its reason" do
    photographed = @user.people.create!(name: "Photo Pal")
    talked = @user.people.create!(name: "Chatty", last_contacted_on: 3.days.ago.to_date)
    birthday = @user.people.create!(name: "Soon", birthday: 10.days.from_now.to_date - 30.years)
    @user.people.create!(name: "Old Contact", created_at: 1.year.ago)
    photo = @user.photos.create!(image: { io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg" })
    photo.photo_people.create!(person: photographed)

    suggestions = People::Picker.for_circle(@user).suggestions

    assert_equal [ photographed, talked, birthday ], suggestions.map(&:person).first(3)
    assert_equal "In 1 photo", suggestions.first.reason
    assert_match(/\ATalked /, suggestions.second.reason)
    assert_match(/\ABirthday /, suggestions.third.reason)
    assert_not_includes suggestions.map { |row| row.person.name }, "Old Contact",
      "long-ago additions with nothing else going for them aren't suggested"
  end

  test "suggestions leave out who's already there" do
    @user.people.create!(name: "In Already", keep_in_touch: true, last_contacted_on: Date.current)

    assert_empty People::Picker.for_circle(@user).suggestions.map(&:person).select(&:keep_in_touch?)
  end

  test "an import's worth of new contacts isn't 'added recently'" do
    (People::Picker::BULK + 1).times { |i| @user.people.create!(name: "Imported #{i}") }

    assert_empty People::Picker.for_circle(@user).suggestions
  end
end
