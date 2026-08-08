require "test_helper"

class CareSettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the tune page lists registry kinds with defaults as placeholders" do
    get care_settings_path
    assert_response :success
    assert_match "Doctor checkup", response.body
    assert_match "Dental", response.body
    assert_match "Add a kind of care", response.body
  end

  test "updating mutes a kind and overrides an interval" do
    patch care_settings_path, params: { kinds: {
      "checkup" => { enabled: "1", interval_months: "" },
      "dental" => { enabled: "1", interval_months: "12" },
      "vision" => { enabled: "0", interval_months: "" }
    } }
    assert_redirected_to care_settings_path

    settings = users(:one).care_settings.index_by(&:kind_key)
    assert_not settings["vision"].enabled?
    assert_equal 12, settings["dental"].interval_months
    assert_nil settings["checkup"].interval_months
  end

  test "adding and removing a custom kind" do
    patch care_settings_path, params: { new_kind: { label: "Dermatology", interval_months: "12" } }

    setting = users(:one).care_settings.custom.sole
    assert_equal "dermatology", setting.kind_key
    assert_equal 12, setting.interval_months

    delete care_setting_path("dermatology")
    assert_empty users(:one).care_settings.custom
  end

  test "a custom kind colliding with the registry is refused" do
    patch care_settings_path, params: { new_kind: { label: "Dental" } }
    assert_empty users(:one).care_settings.custom
  end

  test "unknown kind keys are ignored" do
    patch care_settings_path, params: { kinds: { "evil_key" => { enabled: "0" } } }
    assert_empty users(:one).care_settings
  end
end
