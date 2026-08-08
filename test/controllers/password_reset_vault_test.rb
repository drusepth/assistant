require "test_helper"

# The reset fork (PASSWORDS_PLAN §4.6): with the recovery code nothing is
# lost; without it the loss is explicit, metadata survives, and the vault
# works going forward.
class PasswordResetVaultTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    post credentials_url, params: { credential: { kind: "login", name: "Bank" },
                                    secrets: { password: "sealed-1" } }
    @credential = Credential.last

    post recovery_credentials_url
    @code = response.body[/[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}/]
    delete session_url
  end

  test "reset with the recovery code carries the vault through" do
    put password_url(@user.password_reset_token),
      params: { password: "brand-new", password_confirmation: "brand-new", recovery_code: @code }
    assert_redirected_to new_session_url

    post session_url, params: { email_address: @user.email_address, password: "brand-new" }
    post reveal_credential_url(@credential), params: { field: "password" }
    assert_equal "sealed-1", response.parsed_body["value"]
    assert @user.reload.keyring.recovery_pending? # the used wrap is cleared; a fresh kit gets prompted
  end

  test "reset with a wrong code is rejected, not silently destructive" do
    put password_url(@user.password_reset_token),
      params: { password: "brand-new", password_confirmation: "brand-new", recovery_code: "WRONGX-WRONGX-WRONGX-WRONGX" }

    assert_nil User.authenticate_by(email_address: @user.email_address, password: "brand-new")
    assert_not @credential.reload.secret_lost_for?(@user)
  end

  test "explicit forfeit resets the keyring: secrets lost, metadata intact, vault usable" do
    put password_url(@user.password_reset_token),
      params: { password: "brand-new", password_confirmation: "brand-new", forfeit_vault: "1" }
    assert_redirected_to new_session_url

    post session_url, params: { email_address: @user.email_address, password: "brand-new" }
    assert @credential.reload.secret_lost_for?(@user)
    assert_equal "Bank", @credential.name

    post reveal_credential_url(@credential), params: { field: "password" }
    assert_response :unprocessable_entity

    # The vault works going forward: re-enter the secret via edit.
    patch credential_url(@credential), params: { credential: { name: "Bank" }, secrets: { password: "re-entered" } }
    post reveal_credential_url(@credential), params: { field: "password" }
    assert_equal "re-entered", response.parsed_body["value"]
  end
end
