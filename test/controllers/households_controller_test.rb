require "test_helper"

class HouseholdsControllerTest < ActionDispatch::IntegrationTest
  test "an admin sets the household region (D34)" do
    sign_in_as users(:one)
    patch household_path, params: { household: { region: "Texas, USA" } }

    assert_redirected_to settings_path
    assert_equal "Texas, USA", users(:one).household.reload.region
  end

  test "a non-admin cannot" do
    sign_in_as users(:two)
    patch household_path, params: { household: { region: "Nope" } }

    assert_redirected_to settings_path
    assert_nil users(:two).household.reload.region
  end
end
