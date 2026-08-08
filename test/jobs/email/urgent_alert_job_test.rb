require "test_helper"

class Email::UrgentAlertJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @account = linked_accounts(:alice_email)
    @account.update!(settings: { "alerts" => true })
    @folder = EmailFolder.create!(
      user_id: @user.id, linked_account_id: @account.id,
      name: "INBOX", role: "inbox", uidvalidity: 1, backfilled_at: Time.current)
  end

  def candidate(**overrides)
    message_id = overrides[:message_id] || "urgent-#{SecureRandom.hex(4)}@x"
    EmailMessage.create!(**{
      user_id: @user.id, linked_account_id: @account.id, email_folder: @folder,
      uid: (EmailMessage.maximum(:uid) || 0) + 1, message_id: message_id, thread_key: message_id,
      direction: "inbound", from_email: "clerk@courts.example", from_name: "Alameda Superior Court",
      to_emails: [ "one@example.com" ], subject: "Hearing date changed",
      snippet: "…", body_text: "Your hearing moved to tomorrow 9am.",
      sent_at: 1.hour.ago, importance: 3, triaged_at: 30.minutes.ago,
      triage: { "category" => "time_sensitive", "importance" => 3, "by" => "model" }
    }.merge(overrides))
  end

  def stub_verdict(urgent)
    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: { urgent: urgent }.to_json } } ]
    }.to_json)
  end

  test "a double-confirmed candidate alerts with a header-built payload" do
    message = candidate
    stub_verdict(true)

    Email::UrgentAlertJob.perform_now(@account, [ message.id ])

    assert_not_nil message.reload.alerted_at
    notify = enqueued_jobs.find { |job| job["job_class"] == "NotifyJob" }
    payload = notify["arguments"].to_json
    assert_includes payload, "Hearing date changed"
    assert_includes payload, "Alameda Superior Court"
    assert_not_includes payload, "tomorrow 9am", "bodies never reach notifications"
  end

  test "the skeptical second call vetoes the alert into the digest" do
    message = candidate
    stub_verdict(false)

    assert_no_enqueued_jobs(only: NotifyJob) do
      Email::UrgentAlertJob.perform_now(@account, [ message.id ])
    end
    assert_nil message.reload.alerted_at
  end

  test "alerts are hard-capped per link per day" do
    3.times { candidate(alerted_at: 1.hour.ago) }
    fourth = candidate
    stub_verdict(true)

    assert_no_enqueued_jobs(only: NotifyJob) do
      Email::UrgentAlertJob.perform_now(@account, [ fourth.id ])
    end
    assert_nil fourth.reload.alerted_at
    assert_not_requested :post, ENDPOINT
  end

  test "one alert per thread, ever" do
    candidate(message_id: "root@x", thread_key: "t1", alerted_at: 2.days.ago)
    follow_up = candidate(message_id: "reply@x", thread_key: "t1")
    stub_verdict(true)

    assert_no_enqueued_jobs(only: NotifyJob) do
      Email::UrgentAlertJob.perform_now(@account, [ follow_up.id ])
    end
  end

  test "off by default: without the dial, nothing runs" do
    @account.update!(settings: {})
    message = candidate
    stub_verdict(true)

    assert_no_enqueued_jobs(only: NotifyJob) do
      Email::UrgentAlertJob.perform_now(@account, [ message.id ])
    end
    assert_not_requested :post, ENDPOINT
  end

  test "muted senders, stale mail, and backfill are structurally excluded" do
    @user.email_sender_rules.create!(email: "clerk@courts.example", rule: "mute")
    muted = candidate
    stale = candidate(from_email: "other@x.example", sent_at: 3.days.ago,
      message_id: "stale@x", thread_key: "stale@x")
    history = candidate(from_email: "past@x.example", backfilled: true,
      message_id: "old@x", thread_key: "old@x")
    stub_verdict(true)

    assert_no_enqueued_jobs(only: NotifyJob) do
      Email::UrgentAlertJob.perform_now(@account, [ muted.id, stale.id, history.id ])
    end
    assert_not_requested :post, ENDPOINT
  end
end
