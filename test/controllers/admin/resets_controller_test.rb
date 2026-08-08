require "test_helper"

class Admin::ResetsControllerTest < ActionDispatch::IntegrationTest
  test "the confirmed reset empties the household and signs the admin out" do
    sign_in_as users(:one)
    users(:one).tasks.create!(title: "Dummy data")
    household_id = households(:smith).id

    post admin_reset_path, params: { confirmation: "RESET" }

    assert_not Household.exists?(household_id)
    assert_empty Task.where(title: "Dummy data")
    assert_match(/Household cleared/, flash[:notice])

    get root_path
    assert_redirected_to new_session_path, "the session went with the account"
  end

  test "lands on the signup form when nothing is left on the instance" do
    households(:jones).destroy!
    sign_in_as users(:one)

    post admin_reset_path, params: { confirmation: "RESET" }

    assert_redirected_to setup_path
    follow_redirect!
    assert_response :success
  end

  test "lands on sign-in while another household still exists" do
    sign_in_as users(:one)

    post admin_reset_path, params: { confirmation: "RESET" }

    assert_redirected_to new_session_path
  end

  test "an unconfirmed reset deletes nothing" do
    sign_in_as users(:one)

    assert_no_difference -> { User.count } do
      post admin_reset_path, params: { confirmation: "yes please" }
    end

    assert_redirected_to admin_root_path
    assert_match(/Nothing was deleted/, flash[:alert])
  end

  test "a missing confirmation deletes nothing" do
    sign_in_as users(:one)

    assert_no_difference -> { Household.count } do
      post admin_reset_path
    end

    assert_match(/Nothing was deleted/, flash[:alert])
  end

  test "a non-admin household member cannot reset" do
    sign_in_as users(:two)

    assert_no_difference -> { Household.count } do
      post admin_reset_path, params: { confirmation: "RESET" }
    end

    assert_redirected_to settings_path
  end

  test "signed-out visitors cannot reset" do
    assert_no_difference -> { Household.count } do
      post admin_reset_path, params: { confirmation: "RESET" }
    end

    assert_redirected_to new_session_path
  end

  test "the admin page offers the reset with an honest count" do
    sign_in_as users(:one)
    users(:one).tasks.create!(title: "Dummy data")
    users(:two).notes.create!(body: "More dummy data")

    get admin_root_path

    assert_response :success
    assert_match "Reset this household", response.body
    assert_match "2 items", response.body
    assert_match "2 accounts", response.body
  end
end
