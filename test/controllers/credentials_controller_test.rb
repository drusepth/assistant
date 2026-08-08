require "test_helper"

# The vault's trust-critical paths (PASSWORDS_PLAN W1-W4): unlock rides
# sign-in, secrets only ever leave via the reveal endpoint, sharing keeps
# grant and key row in lockstep, revoke rotates, and no secret ever appears
# in a rendered page body.
class CredentialsControllerTest < ActionDispatch::IntegrationTest
  SECRET = "xK9!distinctive-plaintext-77".freeze

  def sign_in_with_password(user, password: "password")
    post session_url, params: { email_address: user.email_address, password: password }
  end

  def create_credential(name: "Bank", secrets: { password: SECRET })
    post credentials_url, params: { credential: { kind: "login", name: name, username: "drew", url: "bank.example" },
                                    secrets: secrets }
    follow_redirect! # consume the flash so it can't bleed into later asserts
    Credential.last
  end

  setup do
    @user = users(:one)
    sign_in_with_password(@user)
  end

  test "sign-in initializes the keyring and unlocks the vault" do
    assert_not_nil @user.reload.keyring

    get credentials_url
    assert_response :success
    assert_no_match "Vault locked", response.body
  end

  test "create, list, search, and show — with no secret in any page body" do
    credential = create_credential

    get credentials_url
    assert_response :success
    assert_match "Bank", response.body
    assert_no_match SECRET, response.body

    get credentials_url, params: { q: "bank" }
    assert_match "Bank", response.body
    get credentials_url, params: { q: "zzz" }
    assert_no_match ">Bank<", response.body

    get credential_url(credential)
    assert_response :success
    assert_no_match SECRET, response.body
  end

  test "reveal returns the secret as no-store json and touches last_used_at" do
    credential = create_credential

    post reveal_credential_url(credential), params: { field: "password" }
    assert_response :success
    assert_equal SECRET, response.parsed_body["value"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_not_nil credential.reload.last_used_at
  end

  test "totp reveal returns a live code, not the seed" do
    credential = create_credential(secrets: { password: SECRET, totp: "JBSWY3DPEHPK3PXP" })

    post reveal_credential_url(credential), params: { field: "totp" }
    assert_response :success
    assert_match(/\A\d{6}\z/, response.parsed_body["code"])
    assert_nil response.parsed_body["value"]
  end

  test "locking seals reveals; unlocking with the account password reopens" do
    credential = create_credential

    post lock_credentials_url
    post reveal_credential_url(credential), params: { field: "password" }
    assert_response :unauthorized

    post unlock_credentials_url, params: { password: "wrong" }
    post reveal_credential_url(credential), params: { field: "password" }
    assert_response :unauthorized

    post unlock_credentials_url, params: { password: "password" }
    post reveal_credential_url(credential), params: { field: "password" }
    assert_equal SECRET, response.parsed_body["value"]
  end

  test "a fresh session without the unlock cookie sees the banner and locked reveals" do
    credential = create_credential
    sign_out
    sign_in_as(@user) # cookie-only helper: session, no vault unlock

    get credentials_url
    assert_match "Vault locked", response.body
    post reveal_credential_url(credential), params: { field: "password" }
    assert_response :unauthorized
  end

  test "edit merges: blank keeps, filled replaces, remove clears" do
    credential = create_credential(secrets: { password: SECRET, totp: "JBSWY3DPEHPK3PXP", notes: "keep me" })

    patch credential_url(credential), params: {
      credential: { name: "Bank renamed", username: "drew", url: "bank.example" },
      secrets: { password: "", notes: "" }, remove_totp: "1"
    }
    assert_redirected_to credential_url(credential)

    post reveal_credential_url(credential), params: { field: "password" }
    assert_equal SECRET, response.parsed_body["value"]
    post reveal_credential_url(credential), params: { field: "notes" }
    assert_equal "keep me", response.parsed_body["value"]
    assert_not credential.reload.totp_present
  end

  test "another household member can't see or reveal an unshared credential" do
    credential = create_credential
    sign_out
    sign_in_with_password(users(:two))

    get credentials_url
    assert_no_match "Bank", response.body
    post reveal_credential_url(credential), params: { field: "password" }
    assert_response :not_found
  end

  test "share grants visibility and decryptability; revoke rotates the item key" do
    sign_out
    sign_in_with_password(users(:two)) # initialize the grantee's keyring
    sign_out
    sign_in_with_password(@user)
    credential = create_credential

    post share_credential_url(credential), params: { grantee_id: users(:two).id }
    assert_redirected_to credential_url(credential)
    assert credential.credential_keys.exists?(user: users(:two))
    assert AccessGrant.exists?(grantor: @user, grantee: users(:two), subject: credential)

    old_ciphertext = credential.reload.secrets_ciphertext
    sign_out
    sign_in_with_password(users(:two))
    post reveal_credential_url(credential), params: { field: "password" }
    assert_equal SECRET, response.parsed_body["value"]

    sign_out
    sign_in_with_password(@user)
    delete unshare_credential_url(credential), params: { grantee_id: users(:two).id }
    assert_not credential.credential_keys.exists?(user: users(:two))
    refute_equal old_ciphertext, credential.reload.secrets_ciphertext # rotated

    post reveal_credential_url(credential), params: { field: "password" }
    assert_equal SECRET, response.parsed_body["value"] # owner unaffected
  end

  test "sharing with a member who never signed in is refused gently" do
    credential = create_credential

    post share_credential_url(credential), params: { grantee_id: users(:two).id }
    assert_not credential.credential_keys.exists?(user: users(:two))
    assert_not AccessGrant.exists?(grantee: users(:two), subject: credential)
  end

  test "export needs the password and carries the secrets" do
    create_credential

    post export_credentials_url, params: { password: "wrong" }
    assert_redirected_to credentials_url

    post export_credentials_url, params: { password: "password" }
    assert_response :success
    assert_match "login_password", response.body
    assert_match SECRET, response.body
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "import sniffs bitwarden csv, dedupes, and seals secrets" do
    csv = <<~CSV
      folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
      ,,login,Example,my note,,0,https://example.com,me@x.com,imported-pass-1,JBSWY3DPEHPK3PXP
      ,,login,Example,my note,,0,https://example.com,me@x.com,imported-pass-1,
      ,,note,Safe combo,42-13-7,,0,,,,
    CSV

    file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "export.csv")
    assert_difference "Credential.count", 2 do
      post import_credentials_url, params: { file: file }
    end

    imported = @user.credentials.find { |c| c.name == "Example" }
    post reveal_credential_url(imported), params: { field: "password" }
    assert_equal "imported-pass-1", response.parsed_body["value"]
    assert imported.totp_present
  end

  test "health flags common, reused, and weak passwords without storing anything" do
    create_credential(name: "A", secrets: { password: "123456" })
    create_credential(name: "B", secrets: { password: "same-Pass-1" })
    create_credential(name: "C", secrets: { password: "same-Pass-1" })

    get health_credentials_url
    assert_response :success
    assert_match "common", response.body
    assert_match "reused", response.body
  end

  test "recovery kit generates a code and confirm records it" do
    post recovery_credentials_url
    assert_response :success
    assert_match(/[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}/, response.body)

    post recovery_confirm_credentials_url
    assert_not @user.reload.keyring.recovery_pending?
  end

  test "kind registry: a wifi entry seals its password and a card its numbers" do
    post credentials_url, params: { credential: { kind: "wifi", name: "Home wifi", username: "HomeNet" },
                                    secrets: { password: "wifi-pass-9" } }
    wifi = Credential.last
    post reveal_credential_url(wifi), params: { field: "password" }
    assert_equal "wifi-pass-9", response.parsed_body["value"]

    post credentials_url, params: { credential: { kind: "card", name: "Family card", username: "A SMITH" },
                                    secrets: { number: "4111111111111111", expiry: "01/30", code: "123" } }
    card = Credential.last
    get credentials_url
    assert_no_match "4111111111111111", response.body
    post reveal_credential_url(card), params: { field: "number" }
    assert_equal "4111111111111111", response.parsed_body["value"]
  end
end
