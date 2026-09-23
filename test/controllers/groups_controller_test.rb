require "test_helper"

# Groups are People's sub-lenses (docs/PEOPLE.md §6) — the D25 mechanism
# generalized. Same contract as hobbies: custom children only, items
# survive removal minus the tag.
class GroupsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "create adds a group lens under People and lands on its page to fill it" do
    assert_difference "Section.custom.count", 1 do
      post groups_path, params: { name: "Book club" }
    end

    assert_redirected_to section_path("book-club", fresh: 1)
    lens = Section.find_by(slug: "book-club")
    assert_equal sections(:people), lens.parent
  end

  test "create with a blank name explains instead of blowing up" do
    assert_no_difference "Section.count" do
      post groups_path, params: { name: "  " }
    end
    assert_equal "A group needs a name.", flash[:alert]
  end

  test "create is idempotent for an existing group" do
    People::Group.find_or_create!("Book club")

    assert_no_difference "Section.count" do
      post groups_path, params: { name: "book club" }
    end
  end

  test "destroy removes a group; tagged items keep their other tags" do
    lens = People::Group.find_or_create!("Book club")
    event = users(:one).events.create!(title: "Meeting", starts_at: 1.week.from_now)
    event.sections = [ lens, sections(:people) ]

    delete group_path(lens)

    assert_redirected_to section_path("people")
    assert_not Section.exists?(lens.id)
    assert_equal [ sections(:people) ], event.reload.sections.to_a
  end

  test "seeded sections cannot be destroyed" do
    assert_no_difference "Section.count" do
      delete group_path(sections(:budget))
    end
    assert_response :not_found
  end

  test "a group page gets the People tools and its own remove affordance" do
    lens = People::Group.find_or_create!("Book club")

    get section_path(lens.slug)
    assert_response :success
    assert_match "Reconnect with someone", response.body
    assert_match "What do I say?", response.body
    assert_match "Remove this group", response.body
    assert_no_match "Remove this hobby", response.body
  end
end
