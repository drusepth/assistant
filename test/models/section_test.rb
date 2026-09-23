require "test_helper"

class SectionTest < ActiveSupport::TestCase
  test "top_level excludes subsections and orders by position" do
    top = Section.top_level
    assert_includes top, sections(:money)
    assert_not_includes top, sections(:budget)
    assert_equal top.sort_by(&:position), top.to_a
  end

  test "subsections belong to their parent" do
    assert_equal sections(:money), sections(:budget).parent
    assert_includes sections(:rights).children, sections(:disputes)
  end

  test "slug must be unique" do
    duplicate = Section.new(slug: "money", name: "Money Again")
    assert_not duplicate.valid?
  end

  test "seeds build the full locked taxonomy" do
    Rails.application.load_seed

    # Travel is the eighth, added by request (D-travel-facet).
    assert_equal %w[ health hobbies education career people money rights travel ],
      Section.top_level.map(&:slug)
    assert_equal %w[ budget debt taxes assets bills subscriptions benefits ],
      Section.find_by(slug: "money").children.map(&:slug)
    assert_equal %w[ immigration renting voting disputes ],
      Section.find_by(slug: "rights").children.map(&:slug)
  end

  # D-owned-lens: the row says who owns it, so no surface has to ask Pet.
  test "a pet's lens is owned, qualified as a pet, and not an area of People" do
    rex = create_pet(name: "Dimitri")
    club = People::Group.find_or_create!("Book club")
    lens = rex.section

    assert_equal "Pet", lens.owner_type
    assert_not lens.removable?
    assert_equal "Pet · Dimitri", lens.qualified_name
    assert_equal "People · Book club", club.qualified_name
    assert_includes Section.people_groups, club
    assert_not_includes Section.people_groups, lens
    assert_not_includes sections(:people).subsections, lens
  end

  test "a group named like a pet is a new group, never the pet's lens" do
    rex = create_pet(name: "Dimitri")

    group = People::Group.find_or_create!("Dimitri")

    assert_not_equal rex.section, group
    assert_not group.owned?
    assert_nil People::Group.named("dimitri")&.owner_type
  end
end
