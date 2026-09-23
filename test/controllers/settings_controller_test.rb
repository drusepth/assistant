require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "renders sections, sharing, and household" do
    get settings_path
    assert_response :success
    assert_match "Sections", response.body
    assert_match users(:two).name, response.body
  end

  test "the AI card groups self-run providers ahead of cloud ones and recommends running your own" do
    get settings_path
    assert_response :success

    assert_select "select[name=?] optgroup", "model_profile[provider]", count: 2
    assert_select "optgroup[label=?] option[value=?]", "Runs where you put it", "custom"
    assert_select "optgroup[label=?] option[value=?]", "Cloud providers", "anthropic"
    assert_select "optgroup[label=?] option[value=?]", "Cloud providers", "google"

    assert_select "input[type=checkbox][name=?]", "model_profile[allow_cloud_models]"
    assert_match "Allow cloud LLMs", response.body
    assert_match "own the means of your own empowerment", response.body
  end

  test "the photo card offers an upload, and a remove only once there's something to remove" do
    get settings_path
    assert_select "form[action=?][enctype=?]", avatar_path, "multipart/form-data"
    assert_select "a[href=?]", avatar_path, count: 0

    users(:one).avatar.attach(io: file_fixture("photo.jpg").open, filename: "photo.jpg", content_type: "image/jpeg")

    get settings_path
    assert_select "a[href=?]", avatar_path
  end

  test "the work profile saves, normalizes, and clears without touching sections (D-work-profile)" do
    enabled_before = Section.top_level.select { |s| users(:one).section_enabled?(s) }

    patch settings_path, params: { work: { job_title: " Cashier ", employer: "Costco" } }
    assert_redirected_to settings_path
    assert_equal "Cashier", users(:one).reload.job_title
    assert_equal "Costco", users(:one).employer
    assert enabled_before.all? { |s| users(:one).section_enabled?(s) }

    get settings_path
    assert_select "input[name=?][value=?]", "work[job_title]", "Cashier"

    patch settings_path, params: { work: { job_title: "", employer: "" } }
    users(:one).reload
    assert_nil users(:one).job_title
    assert_nil users(:one).employer
  end

  test "units switch between imperial and metric without touching sections" do
    enabled = users(:one).enabled_sections.to_a

    patch settings_path, params: { measurement_system: "metric" }
    assert_redirected_to settings_path
    assert_equal "metric", users(:one).reload.measurement_system

    patch settings_path, params: { measurement_system: "cubits" }
    assert_equal "imperial", users(:one).reload.measurement_system, "an unknown system is the default, never an error"
    assert_equal enabled, users(:one).enabled_sections.to_a

    get settings_path
    assert_select "select[name=measurement_system] option[selected][value=imperial]"
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

  # D-about-pages: household-wide and admin-only, so it takes the same
  # early-return shape as celebrations and must not disturb the sections.
  test "public pages toggle off and back on without touching sections" do
    enabled_before = Section.top_level.select { |s| users(:one).section_enabled?(s) }

    patch settings_path, params: { public_pages: "0" }
    assert_redirected_to settings_path
    assert_not households(:smith).reload.public_pages_enabled?
    assert enabled_before.all? { |s| users(:one).section_enabled?(s) }

    patch settings_path, params: { public_pages: "1" }
    assert households(:smith).reload.public_pages_enabled?
  end

  test "a non-admin cannot touch the public pages switch" do
    sign_in_as users(:two)

    patch settings_path, params: { public_pages: "0" }

    assert_redirected_to settings_path
    assert households(:smith).reload.public_pages_enabled?
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

  test "People's row lists its groups, not the household's pets" do
    create_pet(name: "Dimitri")
    People::Group.find_or_create!("Book club")

    get settings_path

    assert_select "label", text: /Book club/
    assert_select "label", text: /Dimitri/, count: 0
  end
end
