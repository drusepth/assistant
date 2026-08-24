require "test_helper"

# "I saved it" is a click. This is a fact: the code was pasted back and it
# opened the vault. The diary gates on the fact, because a mistyped kit
# there costs the whole journal and nobody else holds a key to restore it.
class RecoveryCheckTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
  end

  def generate_kit
    post recovery_credentials_url
    response.body[/[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}/]
  end

  test "the right code verifies the kit" do
    code = generate_kit
    assert_not @user.reload.keyring.recovery_verified?

    post recovery_check_credentials_url, params: { recovery_code: code }
    assert_redirected_to credentials_path
    assert_match(/right code/i, flash[:notice])
    assert @user.reload.keyring.recovery_verified?
  end

  test "a mistyped code is refused and verifies nothing" do
    generate_kit

    post recovery_check_credentials_url, params: { recovery_code: "WRONGX-WRONGX-WRONGX-WRONGX" }
    assert_match(/doesn't open your vault/i, flash[:alert])
    assert_not @user.reload.keyring.recovery_verified?
  end

  test "formatting of the written-down copy doesn't matter" do
    code = generate_kit

    post recovery_check_credentials_url, params: { recovery_code: code.downcase.tr("-", " ") }
    assert @user.reload.keyring.recovery_verified?
  end

  test "checking works while the vault is locked — which is when you'd reach for it" do
    code = generate_kit
    post lock_credentials_url

    post recovery_check_credentials_url, params: { recovery_code: code }
    assert @user.reload.keyring.recovery_verified?
  end

  test "checking with no kit yet says so" do
    post recovery_check_credentials_url, params: { recovery_code: "ANYTHI-NGATAL-LWOULD-DOHERE" }
    assert_match(/generate a recovery kit first/i, flash[:alert])
  end

  test "a new kit invalidates the old proof" do
    post recovery_check_credentials_url, params: { recovery_code: generate_kit }
    assert @user.reload.keyring.recovery_verified?

    generate_kit
    assert_not @user.reload.keyring.recovery_verified?,
      "a fresh code means the written-down copy is stale, so the proof is too"
  end

  test "a password reset without the code clears the proof" do
    post recovery_check_credentials_url, params: { recovery_code: generate_kit }

    @user.reload.keyring.reset!("a-new-password")
    assert_not @user.keyring.reload.recovery_verified?
  end

  test "the diary refuses to start until the code is proven, not merely promised" do
    generate_kit
    post recovery_confirm_credentials_url # the promise
    assert @user.reload.keyring.recovery_confirmed_at.present?

    get new_diary_entry_url
    assert_redirected_to diary_entries_path
    assert_match(/check your recovery code/i, flash[:alert])
  end

  test "once proven, the diary opens for writing" do
    post recovery_check_credentials_url, params: { recovery_code: generate_kit }

    get new_diary_entry_url
    assert_response :success
  end

  test "the diary's gate offers the check inline" do
    generate_kit

    get diary_entries_url
    assert_response :success
    assert_match "Check your recovery code", response.body
    assert_match recovery_check_credentials_path, response.body
  end

  test "the passwords vault still takes a promise" do
    generate_kit
    post recovery_confirm_credentials_url

    get credentials_url
    assert_response :success
    assert_no_match "No recovery kit saved", response.body
  end
end
