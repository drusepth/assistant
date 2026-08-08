require "test_helper"

# The boomerang family (EMAIL_PLAN.md §7): pure SQL over the mirror,
# gated on declared (reply_wanted_by) or labeled (expects_reply) reply
# expectations — no model, no label, no nudge.
class EmailBoomerangWatchersTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = linked_accounts(:alice_email)
    @folder = EmailFolder.create!(
      user_id: @user.id, linked_account_id: @account.id,
      name: "Sent", role: "sent", uidvalidity: 1, backfilled_at: Time.current)
  end

  def mirror_message(**overrides)
    message_id = overrides[:message_id] || "b-#{SecureRandom.hex(4)}@x"
    EmailMessage.create!(**{
      user_id: @user.id, linked_account_id: @account.id, email_folder: @folder,
      uid: (EmailMessage.maximum(:uid) || 0) + 1, message_id: message_id, thread_key: message_id,
      direction: "outbound", from_email: "one@example.com", to_emails: [ "dana@example.org" ],
      subject: "Deposit return", snippet: "…", body_text: "Could you send it?",
      sent_at: 9.days.ago
    }.merge(overrides))
  end

  test "the user-armed boomerang fires exactly when asked, and not on replied threads" do
    armed = mirror_message(reply_wanted_by: Date.yesterday)
    replied = mirror_message(reply_wanted_by: Date.yesterday, message_id: "r@x", thread_key: "t-replied")
    mirror_message(direction: "inbound", from_email: "dana@example.org", thread_key: "t-replied",
      message_id: "reply@x", sent_at: 1.day.ago)
    mirror_message(reply_wanted_by: Date.tomorrow, message_id: "future@x")

    Watcher::EmailReplyWanted.new(@user).scan

    suggestions = @user.suggestions.where(watcher_slug: "email_reply_wanted")
    assert_equal 1, suggestions.count
    suggestion = suggestions.sole
    assert_match(/Still no reply/, suggestion.title)
    assert_equal "email_follow_up", suggestion.action.dig("tool", "slug")
    assert_equal armed.id.to_s, suggestion.action.dig("tool", "inputs", "email_id")
    assert_not_includes suggestion.title, replied.id.to_s
  end

  test "the inferred no-reply boomerang requires the expects_reply label and skips noise" do
    labeled = mirror_message(expects_reply: true)
    mirror_message(expects_reply: nil, message_id: "unlabeled@x") # no model → no label → quiet
    mirror_message(expects_reply: true, bulk: true, message_id: "bulk@x")
    mirror_message(expects_reply: true, to_emails: [ "no-reply@shop.example" ], message_id: "nr@x")
    mirror_message(expects_reply: true, sent_at: 2.days.ago, message_id: "young@x")

    Watcher::EmailNoReply.new(@user).scan

    suggestions = @user.suggestions.where(watcher_slug: "email_no_reply")
    assert_equal 1, suggestions.count
    assert_equal labeled.id.to_s, suggestions.sole.action.dig("tool", "inputs", "email_id")
    assert_match(/in 9 days/, suggestions.sole.title)
  end

  test "a later outbound message in the thread counts as already followed up" do
    original = mirror_message(expects_reply: true, thread_key: "t-fu", message_id: "orig@x")
    mirror_message(thread_key: "t-fu", message_id: "nudge@x", sent_at: 2.days.ago)

    Watcher::EmailNoReply.new(@user).scan

    assert_equal 0, @user.suggestions.where(watcher_slug: "email_no_reply").count,
      "user already nudged thread #{original.thread_key} themselves"
  end

  test "the inverse boomerang nudges about mail you never answered, muted senders excepted" do
    waiting = mirror_message(direction: "inbound", from_email: "dana@example.org",
      from_name: "Dana", expects_reply: true, sent_at: 5.days.ago, message_id: "ask@x")
    mirror_message(direction: "inbound", from_email: "muted@example.org",
      expects_reply: true, sent_at: 5.days.ago, message_id: "muted@x")
    @user.email_sender_rules.create!(email: "muted@example.org", rule: "mute")
    answered = mirror_message(direction: "inbound", from_email: "carl@example.org",
      expects_reply: true, sent_at: 5.days.ago, message_id: "ans@x", thread_key: "t-ans")
    mirror_message(thread_key: "t-ans", message_id: "myreply@x", sent_at: 1.day.ago)

    Watcher::EmailUnanswered.new(@user).scan

    suggestions = @user.suggestions.where(watcher_slug: "email_unanswered")
    assert_equal 1, suggestions.count
    assert_match(/Dana is waiting/, suggestions.sole.title)
    assert_equal waiting.id.to_s, suggestions.sole.action.dig("tool", "inputs", "email_id")
    assert_not_equal answered.id.to_s, suggestions.sole.action.dig("tool", "inputs", "email_id")
  end

  test "inferred boomerangs cap at three live nudges" do
    5.times do |i|
      mirror_message(expects_reply: true, message_id: "m#{i}@x", thread_key: "t#{i}",
        to_emails: [ "p#{i}@example.org" ])
    end

    Watcher::EmailNoReply.new(@user).scan

    assert_equal 3, @user.suggestions.where(watcher_slug: "email_no_reply").count
  end

  test "dismissing a nudge quiets the thread for the month" do
    mirror_message(expects_reply: true, thread_key: "t-dis", message_id: "d@x")
    watcher = Watcher::EmailNoReply.new(@user)
    watcher.scan
    @user.suggestions.where(watcher_slug: "email_no_reply").sole.dismiss!

    Watcher::EmailNoReply.new(@user).scan

    assert_equal 1, @user.suggestions.where(watcher_slug: "email_no_reply").count,
      "the monthly fingerprint bucket holds"
  end
end
