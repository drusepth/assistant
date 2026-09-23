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
end
