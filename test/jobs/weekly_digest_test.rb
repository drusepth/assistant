require "test_helper"

# M3.3's phrased digest: LLM for phrasing only, deterministic facts in,
# silent failure out.
class WeeklyDigestTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @user.tasks.create!(title: "File the insurance appeal", due_on: Date.current)
  end

  test "the weekly scan stores a phrased digest built from real facts" do
    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: "A steady week. File the insurance appeal first — it's due today." } } ]
    }.to_json)

    AgentScanJob.perform_now(@user, cadence: "weekly")

    @user.reload
    assert_match(/insurance appeal/, @user.digest)
    assert_not_nil @user.digest_generated_at

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("File the insurance appeal") && request.body.include?("ONLY the facts below")
    end
  end

  test "the daily scan never spends a model call on the digest" do
    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: "x" } } ]
    }.to_json)

    AgentScanJob.perform_now(@user, cadence: "daily")

    assert_nil @user.reload.digest
    assert_not_requested :post, ENDPOINT
  end

  test "a failing provider leaves the scan's suggestions intact and the digest empty" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "down")

    AgentScanJob.perform_now(@user, cadence: "weekly")

    @user.reload
    assert_nil @user.digest
    assert_equal 1, @user.suggestions.count, "the deterministic half must survive the LLM half failing"
  end

  test "a household with no configured model skips the digest quietly" do
    AgentScanJob.perform_now(users(:outsider), cadence: "weekly")

    assert_nil users(:outsider).reload.digest
  end
end
