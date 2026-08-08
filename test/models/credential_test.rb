require "test_helper"

class CredentialTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @owner_keyring = Keyring.initialize_for(@owner, "password")
    @owner_key = @owner_keyring.unlock("password")
  end

  test "write and read secrets round-trip through the owner chain" do
    credential = @owner.credentials.create!(name: "Bank", kind: "login", username: "drew")
    credential.write_secrets!({ "password" => "hunter2!", "totp" => "JBSWY3DPEHPK3PXP", "notes" => "pin 1234" })

    secrets = credential.read_secrets(@owner, @owner_key)
    assert_equal "hunter2!", secrets["password"]
    assert_equal "pin 1234", secrets["notes"]
    assert credential.totp_present
    assert_not_nil credential.secret_changed_at
  end

  test "ciphertext never contains the plaintext and metadata is encrypted at rest" do
    credential = @owner.credentials.create!(name: "Streaming Service", kind: "login")
    credential.write_secrets!({ "password" => "correct-horse-battery" })

    assert_no_match(/correct-horse-battery/, credential.secrets_ciphertext)
    raw_name = Credential.connection.select_value("SELECT name FROM credentials WHERE id = #{credential.id}")
    assert_no_match(/Streaming Service/, raw_name.to_s)
  end

  test "another user cannot decrypt without a key row, even with their own vault" do
    credential = @owner.credentials.create!(name: "Bank", kind: "login")
    credential.write_secrets!({ "password" => "s3cret" })

    other = users(:two)
    other_keyring = Keyring.initialize_for(other, "password")

    assert_nil credential.read_secrets(other, other_keyring.unlock("password"))
  end

  test "owner edits keep grantee wraps valid; rotation invalidates them" do
    credential = @owner.credentials.create!(name: "Wifi", kind: "wifi", username: "HomeNet")
    credential.write_secrets!({ "password" => "old-pass" })

    grantee = users(:two)
    grantee_keyring = Keyring.initialize_for(grantee, "password")
    item_key = credential.unwrap_item_key(@owner, @owner_key)
    credential.credential_keys.create!(user: grantee,
      wrapped_item_key: Vault::Crypto.rsa_wrap(grantee_keyring.public_key, item_key))

    credential.update_secrets!({ "password" => "new-pass" }, item_key)
    assert_equal "new-pass", credential.read_secrets(grantee, grantee_keyring.unlock("password"))["password"]

    credential.rotate_secrets!({ "password" => "rotated" }, holders: [ @owner ])
    assert_nil credential.read_secrets(grantee, grantee_keyring.unlock("password"))
    assert_equal "rotated", credential.read_secrets(@owner, @owner_key)["password"]
  end

  test "visibility: item grants share, section grants can never match" do
    credential = @owner.credentials.create!(name: "Bank", kind: "login")
    other = users(:two)

    assert_not credential.visible_to?(other)

    AccessGrant.create!(grantor: @owner, grantee: other, subject: credential)
    assert credential.visible_to?(other)

    # A section-wide share must not leak vault entries (D-passwords-vault):
    # credentials carry no taggings, so the section clause finds nothing.
    money = Section.find_by(slug: "money") || Section.create!(name: "Money", slug: "money", position: 99)
    AccessGrant.create!(grantor: @owner, grantee: users(:two), subject: money)
    fresh = @owner.credentials.create!(name: "Unshared", kind: "login")
    assert_not fresh.visible_to?(other)
  end

  test "destroying a grant destroys the key row with it" do
    credential = @owner.credentials.create!(name: "Bank", kind: "login")
    credential.write_secrets!({ "password" => "x" })
    grantee = users(:two)
    grantee_keyring = Keyring.initialize_for(grantee, "password")
    item_key = credential.unwrap_item_key(@owner, @owner_key)
    credential.credential_keys.create!(user: grantee,
      wrapped_item_key: Vault::Crypto.rsa_wrap(grantee_keyring.public_key, item_key))
    grant = AccessGrant.create!(grantor: @owner, grantee: grantee, subject: credential)

    assert_difference "CredentialKey.count", -1 do
      grant.destroy!
    end
  end

  test "kind is validated and note kind carries only notes" do
    assert_not @owner.credentials.new(name: "x", kind: "bogus").valid?

    note = @owner.credentials.create!(name: "Safe combo", kind: "note")
    note.write_secrets!({ "notes" => "42-13-7" })
    assert_equal({ "notes" => "42-13-7" }, note.read_secrets(@owner, @owner_key))
  end
end
