require "test_helper"

# D37: panels are discovered by slug, never wired into the controller.
class Sections::PanelTest < ActiveSupport::TestCase
  test "built-out sections resolve their panel, others get nil" do
    health = Sections::Panel.for(sections(:health), users(:one))
    assert_instance_of Sections::Panels::Health, health
    assert_equal Health::PANEL_TOOL_SLUGS, health.hidden_tool_slugs
    assert_equal "sections/panels/health", health.partial

    assert_instance_of Sections::Panels::Hobbies, Sections::Panel.for(sections(:hobbies), users(:one))
    assert_instance_of Sections::Panels::Money, Sections::Panel.for(sections(:money), users(:one))
    assert_instance_of Sections::Panels::Budget, Sections::Panel.for(sections(:budget), users(:one))
    assert_nil Sections::Panel.for(sections(:rights), users(:one))
  end

  test "a custom hobby lens slug never resolves a panel" do
    lens = Hobbies::Lens.find_or_create!("Board games")
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
