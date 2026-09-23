require "test_helper"

# D-people-circles: adding someone to a group from the card, the group page,
# or the person page — all the same endpoint. Scoped to People's own custom
# lenses; the item forms' section picker stays the general tagger.
class People::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @group = People::Group.find_or_create!("Book club")
  end

  test "create adds an existing person and says so" do
    rosa = users(:one).people.create!(name: "Rosa")

    post people_memberships_path, params: { section_id: @group.id, person_id: rosa.id }

    assert_includes rosa.reload.sections, @group
    assert_equal "Rosa is in Book club.", flash[:notice]
  end

  test "create takes a new name" do
    assert_difference "Person.count", 1 do
      post people_memberships_path, params: { section_id: @group.id, name: "Rosa" }
    end
    assert_includes Person.find_by(name: "Rosa").sections, @group
  end

  test "create with nothing to go on explains instead of blowing up" do
    assert_no_difference "SectionTagging.count" do
      post people_memberships_path, params: { section_id: @group.id, name: " " }
    end
    assert_equal "Pick someone, or name someone new.", flash[:alert]
  end

  test "destroy takes them out of the group and keeps them in the address book" do
    rosa = users(:one).people.create!(name: "Rosa")
    rosa.sections << @group

    delete people_membership_path(section_id: @group.id, person_id: rosa.id)

    assert_empty rosa.reload.sections
    assert Person.exists?(rosa.id)
  end

  test "seeded sections are not groups" do
    rosa = users(:one).people.create!(name: "Rosa")

    post people_memberships_path, params: { section_id: sections(:health).id, person_id: rosa.id }

    assert_response :not_found
    assert_empty rosa.reload.sections
  end

  test "another section's custom lens is not a group either" do
    hobby = Hobbies::Lens.find_or_create!("Board games")
    rosa = users(:one).people.create!(name: "Rosa")

    post people_memberships_path, params: { section_id: hobby.id, person_id: rosa.id }

    assert_response :not_found
    assert_empty rosa.reload.sections
  end

  test "a pet's lens is not a group anyone can be added to" do
    rex = create_pet(name: "Rex")
    rosa = users(:one).people.create!(name: "Rosa")

    post people_memberships_path, params: { section_id: rex.section_id, person_id: rosa.id }

    assert_response :not_found
    assert_empty rosa.reload.sections
  end

  test "an inline add redraws the group card and the member list in place" do
    rosa = users(:one).people.create!(name: "Rosa")

    post people_memberships_path, params: { section_id: @group.id, person_id: rosa.id, inline: "1" }, as: :turbo_stream

    assert_select "turbo-stream[action=replace][target=?]", "group-#{@group.id}-summary"
    assert_select "turbo-stream[action=replace][target=group-members]" do
      assert_select "template", text: /Rosa/
    end
    assert_match people_membership_path(section_id: @group.id, person_id: rosa.id), response.body
  end
end
