require "test_helper"

class JobFeedsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "pasting a board link adds a feed with its kind sniffed" do
    assert_difference "JobFeed.count", 1 do
      post job_feeds_path, params: { job_feed: { url: "https://boards.greenhouse.io/acme" } }
    end

    feed = users(:one).job_feeds.sole
    assert_equal "greenhouse", feed.kind
    assert_redirected_to section_path("career")
  end

  test "a non-link explains instead of saving" do
    assert_no_difference "JobFeed.count" do
      post job_feeds_path, params: { job_feed: { url: "acme jobs page" } }
    end

    assert_match(/http/, flash[:alert])
  end

  test "removing a feed is scoped to the owner" do
    mine = users(:one).job_feeds.create!(url: "https://example.com/jobs.rss")
    theirs = users(:two).job_feeds.create!(url: "https://example.com/other.rss")

    delete job_feed_path(mine)
    assert_not JobFeed.exists?(mine.id)

    delete job_feed_path(theirs)
    assert_response :not_found
    assert JobFeed.exists?(theirs.id), "another user's feed is untouchable"
  end
end
