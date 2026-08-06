require "test_helper"

class LinkedAccountTest < ActiveSupport::TestCase
  test "a fresh link grants every scope by default" do
    account = linked_accounts(:alice_email)

    assert account.full_access?
    assert_equal %w[ read_inbox read_archive send ], account.enabled_scopes
    assert account.allows?(:read_inbox)
    assert account.allows?("send")
  end

  test "disabling a scope narrows access without touching the others" do
    account = linked_accounts(:alice_email)
    account.update!(disabled_scopes: [ "send" ])

    assert_not account.allows?("send")
    assert account.allows?("read_inbox")
    assert_not account.full_access?
  end

  test "unknown scopes fail closed" do
    assert_not linked_accounts(:alice_email).allows?("delete_everything")
  end

  test "unknown providers are invalid" do
    account = users(:one).linked_accounts.build(provider: "myspace", credentials: { token: "x" })

    assert_not account.valid?
  end

  test "one link per provider per user, but other users can link the same provider" do
    duplicate = users(:one).linked_accounts.build(
      provider: "email", credentials: { host: "h", username: "u", password: "p" })
    assert_not duplicate.valid?

    other = users(:two).linked_accounts.build(
      provider: "email", credentials: { host: "h", username: "u", password: "p" })
    assert other.valid?
  end

  test "every declared credential field is required" do
    account = users(:two).linked_accounts.build(
      provider: "email", credentials: { host: "imap.example.com", username: "bob@example.com" })

    assert_not account.valid?
    assert_includes account.errors.full_messages.to_sentence, "Password"
  end

  test "every provider declares label, fields, and at least one scope" do
    LinkedAccount::PROVIDERS.each do |provider, settings|
      assert settings[:label].present?, "#{provider} has no label"
      assert settings[:fields].any?, "#{provider} has no credential fields"
      assert settings[:scopes].any?, "#{provider} has no scopes"
    end
  end
end
