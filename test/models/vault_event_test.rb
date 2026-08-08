require "test_helper"

# Q-vault-audit, resolved: shares and emergency access are logged; routine
# reveals deliberately are not.
class VaultEventTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @contact = users(:two)
    Keyring.initialize_for(@owner, "password")
    Keyring.initialize_for(@contact, "password")
    @vault_key = @owner.keyring.unlock("password")
    @credential = @owner.credentials.create!(name: "Bank", kind: "login")
    @credential.write_secrets!({ "password" => "s3cret" })
  end

  test "sharing and revoking each leave one owner-visible entry" do
    Vault::Share.new(@credential, @owner, @vault_key).grant([ @contact ])
    Vault::Share.new(@credential, @owner, @vault_key).revoke(@contact)

    events = @owner.vault_events.newest_first
    assert_equal %w[ unshared shared ], events.map(&:action)
    assert_equal [ @contact, @contact ], events.map(&:subject_user)
    assert_match "Shared with Bob Smith", events.last.describe
    assert_match "re-keyed", events.first.describe
  end

  test "the log never carries a secret" do
    Vault::Share.new(@credential, @owner, @vault_key).grant([ @contact ])

    assert_no_match(/s3cret/, @owner.vault_events.map { |e| [ e.describe, e.attributes.to_s ].join }.join)
  end

  test "deleting a credential takes its history with it; vault-wide events survive" do
    Vault::Share.new(@credential, @owner, @vault_key).grant([ @contact ])
    VaultEvent.record("emergency_added", user: @owner, actor: @owner, subject_user: @contact)

    @credential.destroy!

    assert_equal %w[ emergency_added ], @owner.vault_events.map(&:action)
  end

  test "an unknown action is refused and recording never raises" do
    assert_not VaultEvent.new(action: "bogus", user: @owner, actor: @owner).valid?

    assert_nothing_raised do
      assert_nil VaultEvent.record("bogus", user: @owner, actor: @owner)
    end
  end
end
