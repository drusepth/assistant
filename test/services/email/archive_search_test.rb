require "test_helper"

# The read_archive fallback: server-side search, transient results,
# tombstones respected, scope-gated.
class Email::ArchiveSearchTest < ActiveSupport::TestCase
  include EmailFixtureHelper

  setup do
    @account = linked_accounts(:alice_email)
    EmailFolder.create!(
      user_id: users(:one).id, linked_account_id: @account.id,
      name: "INBOX", role: "inbox", uidvalidity: 1, backfilled_at: Time.current)
    @client = FakeImapClient.new({
      "INBOX" => { attrs: [], uidvalidity: 1, messages: {
        5 => rfc822(from: "landlord@example.org", to: "one@example.com",
          subject: "Old inspection notice", body: "The inspection was March 3 last year.",
          message_id: "<ancient@x>", date: 400.days.ago),
        6 => rfc822(from: "spam@example.org", to: "one@example.com",
          subject: "Unrelated", body: "Nothing here.", message_id: "<nope@x>", date: 1.day.ago)
      } } })
  end

  test "finds matching mail on the server without mirroring it" do
    hits = Email::ArchiveSearch.new(@account, client: @client).call([ "inspection" ])

    assert_equal 1, hits.size
    assert_equal "Old inspection notice", hits.first.subject
    assert_includes hits.first.body, "March 3"
    assert_equal 0, EmailMessage.count, "archive results are transient, never mirrored"
  end

  test "fails closed without the read_archive scope, and respects tombstones" do
    @account.update!(disabled_scopes: [ "read_archive" ])
    assert_equal [], Email::ArchiveSearch.new(@account, client: @client).call([ "inspection" ])

    @account.update!(disabled_scopes: [])
    EmailTombstone.create!(linked_account_id: @account.id, message_id: "ancient@x")
    assert_equal [], Email::ArchiveSearch.new(@account, client: @client).call([ "inspection" ]),
      "a removed message stays invisible even through the live search"
  end
end
