require "test_helper"

# D37: panels are discovered by slug, never wired into the controller.
class Sections::PanelTest < ActiveSupport::TestCase
  test "built-out sections resolve their panel, others get nil" do
    health = Sections::Panel.for(sections(:health), users(:one))
    assert_instance_of Sections::Panels::Health, health
    # Plus the pet tools while this household has no pets (Pets.hidden_tool_slugs) —
    # a panel curates its Act zone for who is actually looking.
    assert_equal Health::PANEL_TOOL_SLUGS, health.hidden_tool_slugs - Pets::CARE_TOOL_SLUGS
    assert_equal "sections/panels/health", health.partial

    assert_instance_of Sections::Panels::Hobbies, Sections::Panel.for(sections(:hobbies), users(:one))
    assert_instance_of Sections::Panels::Money, Sections::Panel.for(sections(:money), users(:one))
    assert_instance_of Sections::Panels::Budget, Sections::Panel.for(sections(:budget), users(:one))
    assert_nil Sections::Panel.for(sections(:rights), users(:one))
  end

  # A user-created lens has a slug no class can be named after, so it falls
  # back to its parent's lens panel (D-hobby-feeds) — that is how every hobby
  # page gets a river without the controller learning about hobbies. The
  # hyphen matters: lens slugs are parameterized, and `camelize` alone leaves
  # "Board-games", which resolves to nothing at all.
  test "a custom lens falls back to its parent's lens panel" do
    hobby = Hobbies::Lens.find_or_create!("Board games")
    panel = Sections::Panel.for(hobby, users(:one))

    assert_equal "board-games", hobby.slug
    assert_instance_of Sections::Panels::HobbiesLens, panel
    assert_equal "sections/panels/hobbies_lens", panel.partial
  end

  # A parent that declares no lens class keeps the old answer.
  test "a lens under a parent with no lens panel gets nothing" do
    lens = Sections::Lens.find_or_create!("money", "Side hustle", fallback_slug: "money-lens")

    assert_nil Sections::Panel.for(lens, users(:one))
  end

  # D-people-circles: group slugs are whatever the user typed, so People
  # claims its lenses by parent instead.
  test "a group lens resolves its parent's lens panel" do
    group = People::Group.find_or_create!("Book club")
    panel = Sections::Panel.for(group, users(:one))

    assert_instance_of Sections::Panels::PeopleLens, panel
    assert_equal "sections/panels/people_lens", panel.partial
    assert_equal group, panel.section
  end
end
