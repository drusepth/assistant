require "test_helper"

# Settings › Change password (PASSWORDS_PLAN §4.6): the keyring rewraps in
# the same transaction, so the vault survives a password change untouched.
class UserPasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    post credentials_url, params: { credential: { kind: "login", name: "Bank" },
                                    secrets: { password: "sealed-1" } }
    @credential = Credential.last
  end

  test "change rewraps the keyring and the vault stays open and readable" do
    patch user_password_url, params: { password_challenge: "password",
                                       password: "new-password", password_confirmation: "new-password" }
    assert_redirected_to settings_url

    post reveal_credential_url(@credential), params: { field: "password" }
    assert_equal "sealed-1", response.parsed_body["value"]

    delete session_url
    post session_url, params: { email_address: @user.email_address, password: "new-password" }
    post reveal_credential_url(@credential), params: { field: "password" }
    assert_equal "sealed-1", response.parsed_body["value"]
  end

  test "a wrong current password changes nothing" do
    patch user_password_url, params: { password_challenge: "nope",
                                       password: "new-password", password_confirmation: "new-password" }

    assert_not_nil User.authenticate_by(email_address: @user.email_address, password: "password")
    assert_nil User.authenticate_by(email_address: @user.email_address, password: "new-password")
  end
end
