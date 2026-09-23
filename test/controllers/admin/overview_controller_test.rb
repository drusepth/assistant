require "test_helper"

class Admin::OverviewControllerTest < ActionDispatch::IntegrationTest
  test "an admin sees the hub" do
    sign_in_as users(:one)
    AppError.record(Llm::Error.new("Rate limit reached"), source: "CategorizeTaskJob", user: users(:one))

    get admin_root_path

    assert_response :success
    assert_match "CategorizeTaskJob", response.body
    assert_match "Rate limit reached", response.body
  end

  test "the email card says whether this server sends mail, without its secrets" do
    sign_in_as users(:one)

    get admin_root_path
    assert_match "this server sends no email of its own", response.body

    with_instance_mail(address: "smtp.fastmail.com") do
      ENV["SMTP_PASSWORD"] = "hunter2"
      get admin_root_path
    ensure
      ENV.delete("SMTP_PASSWORD")
    end
    assert_match "Sending through smtp.fastmail.com", response.body
    assert_no_match "hunter2", response.body
  end

  test "a non-admin household member is turned away" do
    sign_in_as users(:two)

    get admin_root_path

    assert_redirected_to settings_path
    assert_equal "Only household admins can do that.", flash[:alert]
  end

  test "signed-out visitors are sent to sign in" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "renders with an empty log" do
    sign_in_as users(:one)

    get admin_root_path

    assert_response :success
    assert_match "Nothing has gone wrong yet", response.body
  end

  test "the sidebar shows the admin link only to admins" do
    sign_in_as users(:one)
    get root_path
    assert_match admin_root_path, response.body

    sign_out
    sign_in_as users(:two)
    get root_path
    assert_no_match admin_root_path, response.body
  end
end
