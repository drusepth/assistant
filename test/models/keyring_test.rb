require "test_helper"

class KeyringTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @keyring = Keyring.initialize_for(@user, "password")
  end

  test "unlocks with the right password, nil with the wrong one" do
    assert_equal 32, @keyring.unlock("password").bytesize
    assert_nil @keyring.unlock("wrong")
  end

  test "the private key comes back only through the vault key" do
    vault_key = @keyring.unlock("password")

    assert_kind_of OpenSSL::PKey::RSA, @keyring.private_key(vault_key)
    assert_raises(Vault::Crypto::Error) { @keyring.private_key(Vault::Crypto.random_key) }
  end

  test "rewrap keeps the same vault key under a new password" do
    vault_key = @keyring.unlock("password")
    @keyring.rewrap!(vault_key, "new-password")

    assert_nil @keyring.unlock("password")
    assert_equal vault_key, @keyring.unlock("new-password")
  end

  test "recovery code unlocks the same vault key" do
    vault_key = @keyring.unlock("password")
    code = @keyring.generate_recovery!(vault_key)

    assert_equal vault_key, @keyring.unlock_with_recovery(code)
    assert_equal vault_key, @keyring.unlock_with_recovery(code.downcase.tr("-", " "))
    assert_nil @keyring.unlock_with_recovery("WRONGX-WRONGX-WRONGX-WRONGX")
    assert @keyring.recovery_pending? # confirmed only when the user says saved
  end

  test "reset issues fresh keys, drops own key rows, and kills escrow both ways" do
    vault_key = @keyring.unlock("password")
    credential = @user.credentials.create!(name: "Bank", kind: "login")
    credential.write_secrets!({ "password" => "s3cret" })

    other = users(:two)
    Keyring.initialize_for(other, "password")
    EmergencyContact.escrow!(owner: @user, contact: other, vault_key: vault_key, wait_days: 7)

    @keyring.reset!("after-reset")

    assert_equal 32, @keyring.reload.unlock("after-reset").bytesize
    refute_equal vault_key, @keyring.unlock("after-reset")
    assert credential.reload.secret_lost_for?(@user)
    assert_empty EmergencyContact.where(user: @user)
    assert_not_nil @keyring.reset_at
  end
end
