require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "renders sections, sharing, and household" do
    get settings_path
    assert_response :success
    assert_match "Sections", response.body
    assert_match users(:two).name, response.body
  end

  test "the photo card offers an upload, and a remove only once there's something to remove" do
    get settings_path
    assert_select "form[action=?][enctype=?]", avatar_path, "multipart/form-data"
    assert_select "a[href=?]", avatar_path, count: 0

    users(:one).avatar.attach(io: file_fixture("photo.jpg").open, filename: "photo.jpg", content_type: "image/jpeg")

    get settings_path
    assert_select "a[href=?]", avatar_path
  end

  test "celebrations toggle off and back on without touching sections" do
    enabled_before = Section.top_level.select { |s| users(:one).section_enabled?(s) }
    assert enabled_before.any?, "fixture user should start with sections enabled"

    patch settings_path, params: { celebrations: "0" }
    assert_redirected_to settings_path
    assert_not users(:one).reload.celebrations?
    assert enabled_before.all? { |s| users(:one).section_enabled?(s) }

    patch settings_path, params: { celebrations: "1" }
    assert users(:one).reload.celebrations?
  end

  test "toggling a section off persists" do
    health = sections(:health)
    enabled_ids = Section.top_level.where.not(id: health.id).ids

    patch settings_path, params: { enabled_section_ids: enabled_ids }
    assert_redirected_to settings_path
    assert_not users(:one).reload.section_enabled?(health)
    assert users(:one).section_enabled?(sections(:money))
  end

  test "dragged section order persists and reorders the sidebar" do
    all_ids = Section.top_level.ids
    new_order = all_ids.rotate

    patch settings_path, params: { enabled_section_ids: all_ids, section_order: new_order }

    assert_redirected_to settings_path
    assert_equal new_order, users(:one).reload.ordered_sections.map(&:id)
    assert_equal new_order, users(:one).enabled_sections.map(&:id)
    assert_equal Section.top_level.ids, users(:two).ordered_sections.map(&:id)
  end

  test "saving without a section order keeps the existing order" do
    users(:one).user_sections.create!(section: sections(:money), enabled: true, position: 1)

    patch settings_path, params: { enabled_section_ids: Section.top_level.ids }

    assert_redirected_to settings_path
    assert_equal sections(:money), users(:one).reload.ordered_sections.first
  end
end
