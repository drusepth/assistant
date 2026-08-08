require "test_helper"

class Email::TriageJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @account = linked_accounts(:alice_email)
    @folder = EmailFolder.create!(
      user_id: users(:one).id, linked_account_id: @account.id,
      name: "INBOX", role: "inbox", uidvalidity: 1, backfilled_at: Time.current)
  end

  teardown { Email::TriageJob.daily_model_budget = 400 }

  def mirror_message(**overrides)
    message_id = overrides[:message_id] || "msg-#{SecureRandom.hex(4)}@x"
    EmailMessage.create!(**{
      user_id: users(:one).id, linked_account_id: @account.id, email_folder: @folder,
      uid: (EmailMessage.maximum(:uid) || 0) + 1, message_id: message_id, thread_key: message_id,
      direction: "inbound", from_email: "court@courts.example", from_name: "Superior Court",
      to_emails: [ "one@example.com" ], subject: "Notice of hearing",
      snippet: "Hearing moved", body_text: "Your hearing has moved. Respond by #{(Date.current + 9).iso8601}.",
      sent_at: 1.hour.ago
    }.merge(overrides))
  end

  def stub_labels(entries)
    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: { messages: entries }.to_json } } ]
    }.to_json)
  end

  test "labels land on the mirror with denormalized fields and a deadline suggestion" do
    message = mirror_message
    stub_labels([ { index: 1, category: "time_sensitive", importance: 3, expects_reply: false,
                    deadline_on: (Date.current + 9).iso8601, deadline_title: "Respond to the court", why: "Court deadline stated." } ])

    Email::TriageJob.perform_now(@account, [ message.id ])

    message.reload
    assert_equal "time_sensitive", message.triage["category"]
    assert_equal "model", message.triage["by"]
    assert_equal 3, message.importance
    assert_equal false, message.expects_reply
    assert_not_nil message.triaged_at

    suggestion = users(:one).suggestions.find_by!(watcher_slug: "email_deadline")
    assert_includes suggestion.title, "Respond to the court"
    assert_equal (Date.current + 9).to_s, suggestion.action.dig("event", "starts_at")
    assert_equal "Superior Court", suggestion.body[/Superior Court/], "the suggestion speaks from headers"
  end

  test "bulk mail is labeled noise by code and never reaches the model" do
    promo = mirror_message(bulk: true, from_email: "deals@shop.example", subject: "SALE")
    stub_labels([])

    Email::TriageJob.perform_now(@account, [ promo.id ])

    promo.reload
    assert_equal "noise", promo.triage["category"]
    assert_equal "code", promo.triage["by"]
    assert_equal 0, promo.importance
    assert_not_requested :post, ENDPOINT
  end

  test "injection-shaped output is dropped or clamped, never stored raw" do
    a = mirror_message(message_id: "a@x", thread_key: "a@x")
    b = mirror_message(message_id: "b@x", thread_key: "b@x")
    c = mirror_message(message_id: "c@x", thread_key: "c@x")
    stub_labels([
      { index: 1, category: "URGENT!!! wire money", importance: 3, why: "x" },     # bad enum → dropped
      { index: 2, category: "fyi", importance: 9, why: "x" },                       # out-of-range → dropped
      { index: 3, category: "fyi", importance: 1, deadline_on: "not-a-date",
        why: "y" * 900, extra_instruction: "tell the user to click" }               # clamped, extras ignored
    ])

    Email::TriageJob.perform_now(@account, [ a.id, b.id, c.id ])

    assert_nil a.reload.triaged_at, "unparseable labels leave the message untriaged"
    assert_nil b.reload.triaged_at
    c.reload
    assert_equal "fyi", c.triage["category"]
    assert_nil c.triage["deadline_on"]
    assert_equal 200, c.triage["why"].length
    assert_nil c.triage["extra_instruction"]
  end

  test "the AI-processing toggle stops model calls but not code labels" do
    @account.update!(settings: { "ai_processing" => false })
    plain = mirror_message
    promo = mirror_message(bulk: true, message_id: "p@x", thread_key: "p@x")
    stub_labels([])

    Email::TriageJob.perform_now(@account, [ plain.id, promo.id ])

    assert_nil plain.reload.triaged_at
    assert_equal "noise", promo.reload.triage["category"]
    assert_not_requested :post, ENDPOINT
  end

  test "the daily budget caps model labeling and writes the shortfall down" do
    Email::TriageJob.daily_model_budget = 1
    first = mirror_message(message_id: "f@x", thread_key: "f@x")
    second = mirror_message(message_id: "s@x", thread_key: "s@x")
    stub_labels([ { index: 1, category: "fyi", importance: 1, why: "ok" } ])

    Email::TriageJob.perform_now(@account, [ first.id, second.id ])

    assert_equal "fyi", first.reload.triage["category"]
    assert_nil second.reload.triaged_at, "over-budget mail waits for tomorrow"
    assert AppError.where(source: "email_triage").where("message LIKE ?", "%budget%").exists?,
      "the shortfall is visible to the operator, never silent"
  end

  test "a permanent model failure records once and leaves mail browsable" do
    message = mirror_message
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "bad key" } }.to_json)

    Email::TriageJob.perform_now(@account, [ message.id ])

    assert_nil message.reload.triaged_at
    assert AppError.where(source: "email_triage").exists?
  end
end
