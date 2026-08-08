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
      provider: "contacts", credentials: { server_url: "https://d.example.com/", username: "u", password: "p" })
    assert_not duplicate.valid?

    other = users(:two).linked_accounts.build(
      provider: "contacts", credentials: { server_url: "https://d.example.com/", username: "u", password: "p" })
    assert other.valid?
  end

  test "multi-link providers allow several links told apart by required labels" do
    creds = { host: "h", username: "u", password: "p" }

    unlabeled = users(:one).linked_accounts.build(provider: "email", credentials: creds)
    assert_not unlabeled.valid?, "a second mailbox needs a label"

    duplicate_label = users(:one).linked_accounts.build(provider: "email", label: "Personal", credentials: creds)
    assert_not duplicate_label.valid?

    work = users(:one).linked_accounts.build(provider: "email", label: "Work", credentials: creds)
    assert work.valid?
    assert_equal "Email — Work", work.display_name
  end

  test "credentials are encrypted at rest but read as a hash" do
    account = users(:two).linked_accounts.create!(
      provider: "email", label: "Personal",
      credentials: { host: "imap.example.com", username: "bob@example.com", password: "s3cret" })

    assert_equal "s3cret", account.reload.credentials["password"]
    raw = LinkedAccount.connection.select_value(
      "SELECT credentials FROM linked_accounts WHERE id = #{account.id}")
    assert_not_includes raw, "s3cret"
    assert_not_includes raw, "imap.example.com"
  end

  test "background sync is due by the provider's cadence and skips paused links" do
    contacts = linked_accounts(:alice_contacts)

    contacts.update!(synced_at: nil)
    assert contacts.sync_due?, "a never-synced syncable link is due"

    contacts.update!(synced_at: 10.minutes.ago)
    assert_not contacts.sync_due?, "an hourly link synced 10 minutes ago is not due"

    contacts.update!(synced_at: 2.hours.ago)
    assert contacts.sync_due?

    contacts.update!(settings: { "paused" => true })
    assert_not contacts.sync_due?, "paused links never sync"

    email = linked_accounts(:alice_email)
    email.update!(synced_at: 20.minutes.ago)
    assert email.sync_due?, "email is due on its faster 15-minute cadence"

    facebook = users(:one).linked_accounts.create!(provider: "facebook", credentials: { access_token: "t" })
    assert_not facebook.sync_due?, "providers without a sync consumer are never due"
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
