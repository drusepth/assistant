require "test_helper"

class HouseholdsControllerTest < ActionDispatch::IntegrationTest
  test "an admin sets the household region (D34) and clock" do
    sign_in_as users(:one)
    patch household_path, params: { household: { region: "Texas, USA", time_zone: "America/Los_Angeles" } }

    assert_redirected_to settings_path
    household = users(:one).household.reload
    assert_equal "Texas, USA", household.region
    assert_equal "America/Los_Angeles", household.time_zone
    assert_equal "America/Los_Angeles", household.tz.name
  end

  test "a non-admin cannot" do
    sign_in_as users(:two)
    patch household_path, params: { household: { region: "Nope", time_zone: "America/New_York" } }

    assert_redirected_to settings_path
    household = users(:two).household.reload
    assert_nil household.region
    assert_not_equal "America/New_York", household.time_zone
  end

  test "an unknown time zone is rejected" do
    sign_in_as users(:one)

    patch household_path, params: { household: { time_zone: "Mars/Olympus_Mons" } }
    assert_equal "UTC", users(:one).household.reload.time_zone
    assert_match(/time zone/, flash[:alert])
  end
end
