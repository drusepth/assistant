require "test_helper"

# D-people-circles: the verb the People page was missing. Membership is
# still a plain section tagging — no join table, no Q17 links.
class People::MembershipTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @group = People::Group.find_or_create!("Book club")
  end

  test "adds someone who already exists" do
    rosa = @user.people.create!(name: "Rosa")

    assert_equal rosa, People::Membership.add(@user, @group, person_id: rosa.id)
    assert_includes rosa.reload.sections, @group
  end

  test "a new name becomes the viewer's own contact, in the group" do
    person = nil
    assert_difference "Person.count", 1 do
      person = People::Membership.add(@user, @group, name: "  Rosa  ")
    end

    assert_equal "Rosa", person.name
    assert_equal @user, person.user
    assert_includes person.sections, @group
  end

  test "adding twice is idempotent — a double-tap can't duplicate" do
    rosa = @user.people.create!(name: "Rosa")
    People::Membership.add(@user, @group, person_id: rosa.id)

    assert_no_difference "SectionTagging.count" do
      People::Membership.add(@user, @group, person_id: rosa.id)
    end
  end

  test "neither a person nor a name is nil, not an exception" do
    assert_nil People::Membership.add(@user, @group, name: "   ")
  end

  test "a person the viewer cannot see cannot be added" do
    theirs = users(:two).people.create!(name: "Unshared")

    assert_nil People::Membership.add(@user, @group, person_id: theirs.id)
    assert_empty theirs.reload.sections
  end

  test "removing drops only this tag" do
    rosa = @user.people.create!(name: "Rosa")
    rosa.sections = [ @group, sections(:health) ]

    assert_equal rosa, People::Membership.remove(@user, @group, person_id: rosa.id)
    assert_equal [ sections(:health) ], rosa.reload.sections.to_a
    assert Person.exists?(rosa.id), "the person survives leaving a group"
  end
end
