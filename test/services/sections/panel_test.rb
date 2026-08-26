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

  # A user-created lens has a slug no class can be named after, so it falls
  # back to its parent's lens panel (D-hobby-feeds) — that is how every hobby
  # page gets a river without the controller learning about hobbies.
  test "a custom lens falls back to its parent's lens panel, or to nothing" do
    hobby = Hobbies::Lens.find_or_create!("Board games")
    panel = Sections::Panel.for(hobby, users(:one))
    assert_instance_of Sections::Panels::HobbiesLens, panel
    assert_equal "sections/panels/hobbies_lens", panel.partial

    group = Sections::Lens.find_or_create!("people", "Book club", fallback_slug: "group")
    assert_nil Sections::Panel.for(group, users(:one)), "People has no lens panel yet"
  end
end
