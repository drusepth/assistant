require "test_helper"

# D37: panels are discovered by slug, never wired into the controller.
class Sections::PanelTest < ActiveSupport::TestCase
  test "built-out sections resolve their panel, others get nil" do
    health = Sections::Panel.for(sections(:health), users(:one))
    assert_instance_of Sections::Panels::Health, health
    assert_equal Health::PANEL_TOOL_SLUGS, health.hidden_tool_slugs
    assert_equal "sections/panels/health", health.partial

    assert_instance_of Sections::Panels::Hobbies, Sections::Panel.for(sections(:hobbies), users(:one))
    assert_nil Sections::Panel.for(sections(:money), users(:one))
  end

  test "a custom hobby lens slug never resolves a panel" do
    lens = Hobbies::Lens.find_or_create!("Board games")
    assert_nil Sections::Panel.for(lens, users(:one))
  end
end
