require "test_helper"

# The D32 scout: feeds in, one ranking call, suggestions out — and only
# suggestions. A lead's accept opens Tailor-my-application; nothing is ever
# applied to on the user's behalf.
class JobScoutWatcherTest < ActiveSupport::TestCase
  LLM = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    Web::Fetch.resolver = Class.new { def getaddresses(_h) = [ "93.184.216.34" ] }.new
  end

  teardown { Web::Fetch.resolver = Resolv }

  test "a matching posting becomes one heads-up whose accept opens the application kit" do
    @user.job_feeds.create!(url: "https://boards.greenhouse.io/acme")
    stub_feed(jobs: [ { title: "Warehouse Lead", absolute_url: "https://boards.greenhouse.io/acme/jobs/1" } ])
    stub_picks([ { index: 0, reason: "Matches your inventory wins and the PC-building hobby's hardware bent." } ])

    suggestion = scan.sole
    assert suggestion.heads_up?
    assert_equal "Job lead: Warehouse Lead at Acme", suggestion.title
    assert_includes suggestion.body, "inventory wins"
    assert_includes suggestion.body, "https://boards.greenhouse.io/acme/jobs/1"
    assert_equal "tailor_application", suggestion.action.dig("tool", "slug")
    assert_equal "https://boards.greenhouse.io/acme/jobs/1", suggestion.action.dig("tool", "inputs", "listing_url")
    assert @user.job_feeds.sole.last_scanned_at.present?
  end

  test "a posting already suggested is never re-ranked or re-proposed" do
    @user.job_feeds.create!(url: "https://boards.greenhouse.io/acme")
    stub_feed(jobs: [ { title: "Warehouse Lead", absolute_url: "https://boards.greenhouse.io/acme/jobs/1" } ])
    stub_picks([ { index: 0, reason: "fit" } ])
    scan

    @user.job_feeds.sole.update!(last_scanned_at: 2.days.ago)
    assert_no_difference "Suggestion.count" do
      Watcher::JobScout.new(@user).scan
    end
    assert_requested :post, LLM, times: 1, &->(_req) { true }
  end

  test "an unreachable feed records its error and the scan stays calm" do
    feed = @user.job_feeds.create!(url: "https://example.com/dead.rss")
    stub_request(:get, "https://example.com/dead.rss").to_return(status: 404, body: "")

    assert_empty scan
    assert_match(/HTTP 404/, feed.reload.last_error)
    assert_not_requested :post, LLM
  end

  test "no feeds, or a model that picks nothing, means silence" do
    assert_empty scan

    @user.job_feeds.create!(url: "https://boards.greenhouse.io/acme")
    stub_feed(jobs: [ { title: "CFO", absolute_url: "https://boards.greenhouse.io/acme/jobs/2" } ])
    stub_picks([])
    assert_empty scan
  end

  private
    def stub_feed(payload)
      stub_request(:get, "https://boards-api.greenhouse.io/v1/boards/acme/jobs")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: payload.to_json)
    end

    def stub_picks(picks)
      stub_request(:post, LLM).to_return(
        status: 200,
        body: { choices: [ { message: { content: { picks: picks }.to_json } } ] }.to_json
      )
    end

    def scan
      Watcher::JobScout.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end
end
