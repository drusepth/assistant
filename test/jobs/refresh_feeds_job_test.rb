require "test_helper"

class RefreshFeedsJobTest < ActiveJob::TestCase
  setup { @user = users(:one) }

  test "the sweep enqueues only the feeds that are actually due" do
    due = @user.feeds.create!(url: "https://example.com/due.xml")
    due.update!(last_fetched_at: 3.hours.ago)
    fresh = @user.feeds.create!(url: "https://example.com/fresh.xml")
    fresh.record_success!
    paused = @user.feeds.create!(url: "https://example.com/paused.xml", active: false)
    paused.update!(last_fetched_at: 3.days.ago)

    assert_enqueued_jobs 1, only: RefreshFeedJob do
      RefreshFeedsJob.refresh_due
    end

    assert_enqueued_with job: RefreshFeedJob, args: [ due ]
  end

  test "a failing feed is skipped until its backoff has passed" do
    feed = @user.feeds.create!(url: "https://example.com/broken.xml")
    3.times { feed.record_failure!("the site answered HTTP 500") }
    feed.update!(last_fetched_at: 90.minutes.ago)

    assert_no_enqueued_jobs only: RefreshFeedJob do
      RefreshFeedsJob.refresh_due
    end
  end

  test "a paused feed is not fetched even when the job is handed one" do
    feed = @user.feeds.create!(url: "https://example.com/paused.xml", active: false)

    RefreshFeedJob.perform_now(feed)

    assert_nil feed.reload.last_fetched_at
  end
end
