require "test_helper"

class Email::ImapSyncTest < ActiveSupport::TestCase
  include EmailFixtureHelper

  setup do
    @account = linked_accounts(:alice_email)
    @user = users(:one)
  end

  def sync!(client)
    Email::ImapSync.new(@account, client: client).call
  end

  def basic_mailbox
    {
      "INBOX" => { attrs: [], uidvalidity: 7, messages: {
        11 => rfc822(from: "dana@example.org", to: "one@example.com", subject: "Deposit return",
                     body: "Can you send the lease?", message_id: "<m1@example.org>", date: 3.days.ago)
      } },
      "Sent" => { attrs: [ :Sent ], uidvalidity: 3, messages: {
        21 => rfc822(from: "one@example.com", to: "dana@example.org", subject: "Re: Deposit return",
                     body: "Here it is.", message_id: "<m2@example.com>", references: "<m1@example.org>", date: 2.days.ago)
      } }
    }
  end

  test "first sync backfills inbox and sent with roles, cursors, and the backfilled flag" do
    client = FakeImapClient.new(basic_mailbox)
    result = sync!(client)

    assert_nil result.error
    assert_not result.more?
    assert client.disconnected? == false, "injected clients are not disconnected by the sync"

    inbox = EmailFolder.inbox.find_by!(linked_account_id: @account.id)
    sent = EmailFolder.sent.find_by!(linked_account_id: @account.id)
    assert_equal "INBOX", inbox.name
    assert_equal "Sent", sent.name
    assert inbox.backfilled? && sent.backfilled?
    assert_equal 11, inbox.last_seen_uid
    assert_equal 7, inbox.uidvalidity

    assert_equal 2, EmailMessage.where(linked_account_id: @account.id).count
    message = EmailMessage.find_by!(message_id: "m1@example.org")
    assert message.backfilled?, "backfill-phase messages carry the flag"
    assert_equal "inbound", message.direction
    assert_equal "dana@example.org", message.from_email
    assert_equal "Deposit return", message.subject
    assert_includes message.body_text, "lease"
    assert_equal [], result.new_live_ids, "backfill never counts as live arrivals"
  end

  test "live sync ingests only new uids and reports them as live arrivals" do
    client = FakeImapClient.new(basic_mailbox)
    sync!(client)

    client.mailbox["INBOX"][:messages][12] = rfc822(
      from: "landlord@example.org", to: "one@example.com", subject: "Inspection Friday",
      body: "The inspection moved to Friday 9am.", message_id: "<m3@example.org>", date: 1.hour.ago)
    result = sync!(client)

    fresh = EmailMessage.find_by!(message_id: "m3@example.org")
    assert_not fresh.backfilled?
    assert_equal [ fresh.id ], result.new_live_ids
    assert_equal 12, EmailFolder.inbox.find_by!(linked_account_id: @account.id).last_seen_uid
  end

  test "message_id dedupe survives a UIDVALIDITY reset without duplicating the mirror" do
    client = FakeImapClient.new(basic_mailbox)
    sync!(client)

    client.mailbox["INBOX"][:uidvalidity] = 99
    sync!(client)

    assert_equal 1, EmailMessage.where(message_id: "m1@example.org").count
    inbox = EmailFolder.inbox.find_by!(linked_account_id: @account.id)
    assert_equal 99, inbox.uidvalidity
    assert inbox.backfilled?
  end

  test "tombstoned messages never resurrect" do
    client = FakeImapClient.new(basic_mailbox)
    sync!(client)

    message = EmailMessage.find_by!(message_id: "m1@example.org")
    message.remove_from_mirror!
    assert EmailTombstone.covers?(@account.id, "m1@example.org")

    client.mailbox["INBOX"][:uidvalidity] = 42 # force a full re-mirror
    sync!(client)

    assert_nil EmailMessage.find_by(message_id: "m1@example.org")
  end

  test "sent-folder aliases are learned and drive direction on inbox copies" do
    mailbox = basic_mailbox
    mailbox["Sent"][:messages][22] = rfc822(
      from: "alias@otherdomain.example", to: "dana@example.org", subject: "From my alias",
      body: "Sent under the alias.", message_id: "<m4@x>", date: 1.day.ago)
    mailbox["INBOX"][:messages][13] = rfc822(
      from: "alias@otherdomain.example", to: "one@example.com", subject: "Self-cc",
      body: "A copy of my own alias mail.", message_id: "<m5@x>", date: 1.day.ago)
    sync!(FakeImapClient.new(mailbox))

    assert_includes @account.reload.setting(:own_addresses), "alias@otherdomain.example"
    assert_equal "outbound", EmailMessage.find_by!(message_id: "m5@x").direction,
      "a learned alias makes even an inbox copy outbound"
  end

  test "messages match the user's People by counterparty address" do
    person = @user.people.create!(name: "Dana", email: "dana@example.org")
    sync!(FakeImapClient.new(basic_mailbox))

    inbound = EmailMessage.find_by!(message_id: "m1@example.org")
    outbound = EmailMessage.find_by!(message_id: "m2@example.com")
    assert_equal person, inbound.person, "inbound matches the sender"
    assert_equal person, outbound.person, "outbound matches the first recipient"
  end

  test "threading: references root wins; the subject fallback only merges identical participants" do
    mailbox = basic_mailbox
    mailbox["INBOX"][:messages][14] = rfc822(
      from: "dana@example.org", to: "one@example.com", subject: "Re: Deposit return",
      body: "Thanks, got it.", message_id: "<m6@x>", references: "<m1@example.org>", date: 1.day.ago)
    mailbox["INBOX"][:messages][15] = rfc822(
      from: "stranger@elsewhere.example", to: "one@example.com", subject: "Re: Deposit return",
      body: "Unrelated thread, same subject.", message_id: "<m7@x>", date: 1.day.ago)
    sync!(FakeImapClient.new(mailbox))

    root = EmailMessage.find_by!(message_id: "m1@example.org")
    reply = EmailMessage.find_by!(message_id: "m6@x")
    stranger = EmailMessage.find_by!(message_id: "m7@x")

    assert_equal root.thread_key, reply.thread_key
    assert_not_equal root.thread_key, stranger.thread_key,
      "same 'Re:' subject from different participants must not merge"
  end

  test "bulk mail is flagged at ingest" do
    mailbox = basic_mailbox
    mailbox["INBOX"][:messages][16] = rfc822(
      from: "deals@shop.example", to: "one@example.com", subject: "50% off everything",
      body: "Buy now.", message_id: "<promo@x>", list_unsubscribe: "<https://shop.example/u>", date: 1.day.ago)
    mailbox["INBOX"][:messages][17] = rfc822(
      from: "noreply@service.example", to: "one@example.com", subject: "Your receipt",
      body: "Thanks for your payment.", message_id: "<receipt@x>", date: 1.day.ago)
    sync!(FakeImapClient.new(mailbox))

    assert EmailMessage.find_by!(message_id: "promo@x").bulk?
    assert EmailMessage.find_by!(message_id: "receipt@x").bulk?
    assert_not EmailMessage.find_by!(message_id: "m1@example.org").bulk?
  end

  test "flag refresh keeps seen and answered truthful on recent mail" do
    client = FakeImapClient.new(basic_mailbox)
    sync!(client)

    client.flag_map = { "INBOX" => { 11 => [ :Seen, :Answered ] } }
    sync!(client)

    message = EmailMessage.find_by!(message_id: "m1@example.org")
    assert message.seen?
    assert message.answered?
  end

  test "sync fails closed when the read_inbox scope is off" do
    @account.update!(disabled_scopes: [ "read_inbox" ])

    error = assert_raises(Email::ImapSync::Error) { sync!(FakeImapClient.new(basic_mailbox)) }
    assert_match(/switched off/, error.message)
    assert_equal 0, EmailMessage.where(linked_account_id: @account.id).count
  end

  test "html bodies are stripped to text" do
    mailbox = basic_mailbox
    mailbox["INBOX"][:messages][18] = rfc822(
      from: "dana@example.org", to: "one@example.com", subject: "HTML mail",
      body: "<div><p>Hello <b>there</b></p><script>evil()</script></div>",
      message_id: "<html@x>", html: true, date: 1.day.ago)
    sync!(FakeImapClient.new(mailbox))

    body = EmailMessage.find_by!(message_id: "html@x").body_text
    assert_includes body, "Hello there"
    assert_not_includes body, "<p>"
    assert_not_includes body, "evil()"
  end

  test "unlinking purges the mirror; promoted primitives survive" do
    sync!(FakeImapClient.new(basic_mailbox))
    message = EmailMessage.find_by!(message_id: "m1@example.org")
    task = @user.tasks.create!(title: "Send the lease")
    EmailMessageItem.create!(email_message: message, item_type: "Task", item_id: task.id)

    @account.destroy!

    assert_equal 0, EmailMessage.where(linked_account_id: @account.id).count
    assert_equal 0, EmailFolder.where(linked_account_id: @account.id).count
    assert_equal 0, EmailMessageItem.count
    assert Task.exists?(task.id), "promotion copies content out — the primitive never depends on the mirror"
  end

  test "the nightly prune honors the window and its keep-exceptions" do
    sync!(FakeImapClient.new(basic_mailbox))
    old_kept, old_armed, old_doomed = 3.times.map do |i|
      EmailMessage.create!(
        user_id: @user.id, linked_account_id: @account.id,
        email_folder: EmailFolder.inbox.find_by!(linked_account_id: @account.id),
        uid: 100 + i, message_id: "old#{i}@x", thread_key: "old#{i}@x",
        direction: "inbound", sent_at: 200.days.ago, backfilled: true)
    end
    task = @user.tasks.create!(title: "kept")
    EmailMessageItem.create!(email_message: old_kept, item_type: "Task", item_id: task.id)
    old_armed.update!(reply_wanted_by: Date.tomorrow)

    Email::PruneMirrorJob.perform_now(@account)

    assert EmailMessage.exists?(old_kept.id), "promoted rows are kept"
    assert EmailMessage.exists?(old_armed.id), "reply-armed rows are kept"
    assert_not EmailMessage.exists?(old_doomed.id)
    assert EmailMessage.exists?(message_id: "m1@example.org"), "in-window rows are untouched"
  end

  test "search finds mirrored mail and respects removal" do
    sync!(FakeImapClient.new(basic_mailbox))
    message = EmailMessage.find_by!(message_id: "m1@example.org")

    ids = Email::Search.match_ids("lease")
    if ids.nil?
      skip "SQLite build without FTS5 — LIKE fallback covered elsewhere"
    else
      assert_includes ids.map(&:to_i), message.id
      message.remove_from_mirror!
      assert_not_includes Email::Search.match_ids("lease").map(&:to_i), message.id
    end
  end
end
