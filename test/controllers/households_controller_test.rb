require "test_helper"

class HouseholdsControllerTest < ActionDispatch::IntegrationTest
  test "an admin can set the household clock and region" do
    sign_in_as users(:one)

    patch household_path, params: { household: { time_zone: "America/Los_Angeles", region: "California, US" } }
    assert_redirected_to settings_path

    household = users(:one).household.reload
    assert_equal "America/Los_Angeles", household.time_zone
    assert_equal "California, US", household.region
    assert_equal "America/Los_Angeles", household.tz.name
  end

  test "non-admins cannot change household settings" do
    sign_in_as users(:two)

    patch household_path, params: { household: { time_zone: "America/New_York" } }
    assert_redirected_to settings_path
    assert_not_equal "America/New_York", users(:two).household.reload.time_zone
  end

  test "an unknown time zone is rejected" do
    sign_in_as users(:one)

    patch household_path, params: { household: { time_zone: "Mars/Olympus_Mons" } }
    assert_equal "UTC", users(:one).household.reload.time_zone
    assert_match(/time zone/, flash[:alert])
  end
end
