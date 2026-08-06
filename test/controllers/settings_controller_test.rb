require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "renders sections, sharing, and household" do
    get settings_path
    assert_response :success
    assert_match "Sections", response.body
    assert_match users(:two).name, response.body
  end

  test "toggling a section off persists" do
    health = sections(:health)
    enabled_ids = Section.top_level.where.not(id: health.id).ids

    patch settings_path, params: { enabled_section_ids: enabled_ids }
    assert_redirected_to settings_path
    assert_not users(:one).reload.section_enabled?(health)
    assert users(:one).section_enabled?(sections(:money))
  end
end
