require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "without instance mail, the page names who can hand over a link instead of offering a form" do
    get new_password_path

    assert_select "form[action='#{passwords_path}']", count: 0
    assert_select "p", /doesn't send email/
    assert_select "code", /password:reset_link/
  end

  test "with instance mail, the page offers the email form" do
    with_instance_mail do
      get new_password_path
      assert_select "form[action='#{passwords_path}']"
    end
  end

  test "create" do
    with_instance_mail do
      post passwords_path, params: { email_address: @user.email_address }
      assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    with_instance_mail do
      post passwords_path, params: { email_address: "missing-user@example.com" }
      assert_enqueued_emails 0
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create without instance mail sends nothing and says so" do
    post passwords_path, params: { email_address: @user.email_address }

    assert_enqueued_emails 0
    assert_redirected_to new_password_path
    follow_redirect!
    assert_notice "doesn't send email"
  end

  test "a handed-over reset link opens the same form and works once" do
    token = @user.handed_password_reset_token

    get edit_password_path(token)
    assert_response :success

    put password_path(token), params: { password: "brand-new", password_confirmation: "brand-new" }
    assert_redirected_to new_session_path
    assert @user.reload.authenticate("brand-new")

    get edit_password_path(token)
    assert_redirected_to new_password_path
  end

  test "a handed-over reset link lasts a day, not fifteen minutes" do
    token = @user.handed_password_reset_token

    travel 23.hours do
      get edit_password_path(token)
      assert_response :success
    end
    travel 25.hours do
      get edit_password_path(token)
      assert_redirected_to new_password_path
    end
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "new", password_confirmation: "new" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no", password_confirmation: "match" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Passwords did not match"
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/
    end
end
