require "test_helper"

class MailControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = linked_accounts(:alice_email)
    @folder = EmailFolder.create!(
      user_id: users(:one).id, linked_account_id: @account.id,
      name: "INBOX", role: "inbox", uidvalidity: 1, backfilled_at: Time.current)
  end

  def mirror_message(**overrides)
    message_id = overrides[:message_id] || "msg-#{SecureRandom.hex(4)}@example.org"
    defaults = {
      user_id: users(:one).id, linked_account_id: @account.id, email_folder: @folder,
      uid: (EmailMessage.maximum(:uid) || 0) + 1,
      message_id: message_id, thread_key: message_id,
      direction: "inbound", from_email: "dana@example.org", from_name: "Dana",
      to_emails: [ "one@example.com" ], subject: "Deposit return",
      snippet: "Can you send the lease?", body_text: "Can you send the lease? Thanks, Dana.",
      sent_at: 2.days.ago
    }
    EmailMessage.create!(**defaults.merge(overrides))
  end

  test "index lists mirrored threads" do
    mirror_message
    sign_in_as users(:one)

    get mail_index_path
    assert_response :success
    assert_match "Deposit return", response.body
    assert_match "Dana", response.body
  end

  test "index search narrows to matching mail" do
    mirror_message
    mirror_message(subject: "Totally unrelated", snippet: "picnic", body_text: "About the picnic.",
                   message_id: "other@example.org", thread_key: "other@example.org")
    sign_in_as users(:one)

    get mail_index_path, params: { q: "lease" }
    assert_response :success
    assert_match "Deposit return", response.body
    assert_no_match(/Totally unrelated/, response.body)
  end

  test "show renders the thread with promotion actions" do
    message = mirror_message
    sign_in_as users(:one)

    get mail_path(message)
    assert_response :success
    assert_match "Can you send the lease?", response.body
    assert_match "Remove from mirror", response.body
  end

  test "another user's mail is not reachable" do
    message = mirror_message
    sign_in_as users(:two)
    users(:two).linked_accounts.create!(provider: "email", label: "Personal",
      credentials: { host: "h", username: "two@example.com", password: "p" })

    get mail_path(message)
    assert_response :not_found
  end

  test "without a linked mailbox, mail redirects to settings" do
    sign_in_as users(:two)

    get mail_index_path
    assert_redirected_to settings_path
  end

  test "promoting to a task copies content out and records provenance" do
    message = mirror_message
    sign_in_as users(:one)

    assert_difference("Task.count") do
      post promote_mail_path(message, kind: "task")
    end
    task = Task.order(:id).last
    assert_includes task.title, "Deposit return"
    assert_equal [ task ], message.reload.promoted_items
  end

  test "promoting to an event lands an all-day calendar event on the chosen day" do
    message = mirror_message
    sign_in_as users(:one)

    assert_difference("Event.count") do
      post promote_mail_path(message, kind: "event", date: "2026-09-01")
    end
    event = Event.order(:id).last
    assert event.all_day?
    assert_equal Date.new(2026, 9, 1), event.starts_at.to_date
  end

  test "promoting to a note carries the body and provenance line" do
    message = mirror_message
    sign_in_as users(:one)

    assert_difference("Note.count") do
      post promote_mail_path(message, kind: "note")
    end
    note = Note.order(:id).last
    assert_includes note.body, "Can you send the lease?"
    assert_includes note.body, "From email from Dana"
  end

  test "remind arms the user boomerang on outbound mail only" do
    outbound = mirror_message(direction: "outbound", from_email: "one@example.com",
      to_emails: [ "dana@example.org" ], message_id: "out@example.com", thread_key: "out@example.com")
    inbound = mirror_message(message_id: "in@example.org", thread_key: "in@example.org")
    sign_in_as users(:one)

    post remind_mail_path(outbound), params: { on: 1.week.from_now.to_date.iso8601 }
    assert_equal 1.week.from_now.to_date, outbound.reload.reply_wanted_by

    post remind_mail_path(inbound), params: { on: 1.week.from_now.to_date.iso8601 }
    assert_nil inbound.reload.reply_wanted_by
    assert_match(/mail you sent/, flash[:alert])
  end

  test "destroy removes from the mirror and tombstones" do
    message = mirror_message
    sign_in_as users(:one)

    delete mail_path(message)
    assert_redirected_to mail_index_path
    assert_not EmailMessage.exists?(message.id)
    assert EmailTombstone.covers?(@account.id, message.message_id)
  end
end
