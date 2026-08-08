require "test_helper"

class Email::DigestJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @account = linked_accounts(:alice_email)
    @folder = EmailFolder.create!(
      user_id: @user.id, linked_account_id: @account.id,
      name: "INBOX", role: "inbox", uidvalidity: 1, backfilled_at: Time.current)
  end

  def important_message(**overrides)
    message_id = overrides[:message_id] || "digest-#{SecureRandom.hex(4)}@x"
    EmailMessage.create!(**{
      user_id: @user.id, linked_account_id: @account.id, email_folder: @folder,
      uid: (EmailMessage.maximum(:uid) || 0) + 1, message_id: message_id, thread_key: message_id,
      direction: "inbound", from_email: "court@courts.example", from_name: "Superior Court",
      to_emails: [ "one@example.com" ], subject: "Hearing moved", snippet: "…", body_text: "…",
      sent_at: 2.hours.ago, importance: 3, triaged_at: 1.hour.ago,
      triage: { "category" => "time_sensitive", "importance" => 3, "why" => "Court deadline.", "by" => "model" }
    }.merge(overrides))
  end

  test "the digest stores selected items with a phrased line and stamps the day" do
    important_message
    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: "The court moved your hearing — look at that first." } } ]
    }.to_json)

    Email::DigestJob.perform_now(@user)

    digest = @user.reload.mail_digest
    assert_equal Date.current.iso8601, digest["date"]
    assert_equal 1, digest["items"].size
    assert_equal "Superior Court", digest["items"].first["from"]
    assert_match(/hearing/, digest["phrased"])
    assert_equal Date.current, @user.mail_digest_generated_on
  end

  test "a quiet day stores nothing, sends nothing, and spends nothing" do
    important_message(importance: 1)
    stub_request(:post, ENDPOINT).to_return(status: 500)

    assert_no_enqueued_jobs(only: NotifyJob) { Email::DigestJob.perform_now(@user) }

    assert_nil @user.reload.mail_digest
    assert_equal Date.current, @user.mail_digest_generated_on, "the day is stamped so it isn't re-attempted"
    assert_not_requested :post, ENDPOINT
  end

  test "the notification pointer is opt-in and header-built" do
    @user.update!(mail_digest_notify: true)
    important_message
    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: "Phrased." } } ]
    }.to_json)

    Email::DigestJob.perform_now(@user)

    notify = enqueued_jobs.find { |job| job["job_class"] == "NotifyJob" }
    assert notify, "digest notify pointer should be enqueued"
    payload = notify["arguments"].to_json
    assert_includes payload, "Superior Court"
    assert_not_includes payload, "Phrased.", "model prose never reaches a notification (D22/§8)"
  end

  test "digest-excluded links contribute nothing" do
    @account.update!(settings: { "digest" => false })
    important_message
    stub_request(:post, ENDPOINT).to_return(status: 500)

    Email::DigestJob.perform_now(@user)

    assert_nil @user.reload.mail_digest
  end

  test "the dispatcher fires at the user's local hour, once per day" do
    important_message
    @user.household.update!(time_zone: "UTC")
    @user.update!(mail_digest_hour: 8)
    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: "x" } } ]
    }.to_json)

    travel_to Time.utc(2026, 8, 10, 6, 0) do
      assert_no_enqueued_jobs(only: Email::DigestJob) { Email::DigestJob.dispatch_due }
    end

    travel_to Time.utc(2026, 8, 10, 8, 10) do
      assert_enqueued_with(job: Email::DigestJob) { Email::DigestJob.dispatch_due }
      perform_enqueued_jobs(only: Email::DigestJob)
      assert_no_enqueued_jobs(only: Email::DigestJob) { Email::DigestJob.dispatch_due }
    end
  end
end
