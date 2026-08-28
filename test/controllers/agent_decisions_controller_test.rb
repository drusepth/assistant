require "test_helper"

# The page a notification's one-tap link opens (D-decision-links). The
# security property under test is that the token grants nothing: it names
# suggestions, and the session decides whose they are.
class AgentDecisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @suggestion = @user.suggestions.create!(
      watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/dental",
      title: "Book a dental cleaning", body: "Your last cleaning was in February.",
      action: { "task" => { "title" => "Book a dental cleaning" } }
    )
    @token = Notifications::DecisionLink.token_for([ @suggestion.id ])
  end

  test "the owner sees the batch, with the body the notification could not carry" do
    sign_in_as @user

    get agent_decision_path(token: @token)

    assert_response :success
    assert_select "body", /Book a dental cleaning/
    assert_select "body", /Your last cleaning was in February/
  end

  test "a signed-out visitor is asked to sign in and lands here afterwards" do
    get agent_decision_path(token: @token)

    assert_redirected_to new_session_path

    # The leaked-URL case: the page itself never rendered anything.
    follow_redirect!
    assert_select "body", { text: /Book a dental cleaning/, count: 0 }
  end

  test "another household member's session sees nothing of someone else's batch" do
    sign_in_as users(:two)

    get agent_decision_path(token: @token)

    assert_response :success
    assert_select "body", /Nothing left to decide/
    assert_select "body", { text: /Book a dental cleaning/, count: 0 }
  end

  test "a decision already made is not offered again" do
    sign_in_as @user
    @suggestion.dismiss!

    get agent_decision_path(token: @token)

    assert_response :success
    assert_select "body", /Nothing left to decide/
  end

  test "acting from the link works like acting anywhere else" do
    sign_in_as @user

    assert_difference -> { @user.tasks.count } do
      patch accept_suggestion_path(@suggestion)
    end

    assert_predicate @suggestion.reload, :accepted?
  end

  test "an expired or tampered token sends the user somewhere useful instead of erroring" do
    sign_in_as @user

    get agent_decision_path(token: "nonsense")

    assert_redirected_to root_path
  end

  test "the scan hands the notification a link for the batch it just made" do
    Section.top_level.each do |section|
      @user.user_sections.find_or_initialize_by(section: section).update!(agent_level: :active, enabled: true)
    end
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 500, body: "down")

    AgentScanJob.perform_now(@user, cadence: "daily")

    enqueued = enqueued_jobs.find { |job| job["job_class"] == "NotifyJob" }
    ids = enqueued.dig("arguments", 2, "suggestion_ids")
    assert ids.present?, "the notification carries the batch, so the link can point at it"
  end
end
