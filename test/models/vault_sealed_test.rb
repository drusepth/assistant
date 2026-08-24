require "test_helper"

# The extraction's own contract (D-vault-sealed). The proof that it changed
# no password behavior is the untouched credential/keyring/controller suite;
# these cover the seams the extraction introduced.
class VaultSealedTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @keyring = Keyring.initialize_for(@owner, "password")
    @vault_key = @keyring.unlock("password")
  end

  # The one that matters: a container that includes the concern but never
  # joins the registry would survive a password reset with live wrapped keys
  # behind a vault the user was told is dead.
  test "every sealed container is in the registry Keyring#reset! walks" do
    Rails.application.eager_load!

    including = ApplicationRecord.descendants.select { |model| model.include?(VaultSealed) }.map(&:name)
    assert_includes including, "Credential", "sanity: the suite found no sealed models at all"

    (including - VaultSealed::CONTAINERS).each do |missing|
      flunk "#{missing} includes VaultSealed but is not in VaultSealed::CONTAINERS — " \
            "a password reset would leave its wrapped keys alive"
    end
  end

  test "registry entries all resolve and answer the reset hook" do
    VaultSealed::CONTAINERS.each do |name|
      container = name.constantize
      assert container.respond_to?(:mark_lost_on_reset!), "#{name} must answer mark_lost_on_reset!"
      assert_kind_of ActiveRecord::Reflection::AbstractReflection, container.sealed_key_reflection
    end
  end

  test "the sealed key class and foreign key are derived from the association" do
    assert_equal CredentialKey, Credential.sealed_key_class
    assert_equal "credential_id", Credential.sealed_key_foreign_key
  end

  test "payload is bound to its AAD: a blob moved between kinds fails its tag" do
    login = @owner.credentials.create!(name: "Bank", kind: "login")
    login.write_secrets!({ "password" => "hunter2" })
    item_key = login.unwrap_item_key(@owner, @vault_key)

    sealed_note = @owner.credentials.create!(name: "Note", kind: "note")
    sealed_note.update_column(:secrets_ciphertext, login.secrets_ciphertext)

    assert_equal "hunter2", login.read_secrets_with_item_key(item_key)["password"]
    assert_nil sealed_note.reload.read_secrets_with_item_key(item_key),
      "a ciphertext read under a different kind's AAD must not decrypt"
  end

  test "wrap_item_key_for! skips a holder with no keyring rather than raising" do
    credential = @owner.credentials.create!(name: "Bank", kind: "login")
    credential.write_secrets!({ "password" => "x" })
    item_key = credential.unwrap_item_key(@owner, @vault_key)

    keyringless = users(:two)
    assert_nil keyringless.keyring
    assert_nothing_raised { credential.wrap_item_key_for!(keyringless, item_key) }
    assert_not credential.sealed_keys.exists?(user: keyringless)
  end

  test "sealed_keys reaches the container's own key rows" do
    credential = @owner.credentials.create!(name: "Bank", kind: "login")
    credential.write_secrets!({ "password" => "x" })

    assert_equal credential.credential_keys.to_a, credential.sealed_keys.to_a
  end
end
