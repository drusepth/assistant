require "test_helper"

# Where a feed goes the moment it exists (D-hobby-feeds), including the case
# the whole design is built around: an instance with no model configured.
class Feeds::FilingTest < ActiveJob::TestCase
  LLM = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @wood = Hobbies::Lens.find_or_create!("Woodworking")
  end

  test "a feed the user filed by hand is never second-guessed" do
    feed = @user.feeds.create!(url: "https://example.com/wood.xml", sections: [ @wood ])

    assert_no_enqueued_jobs(only: ClassifyFeedJob) { Feeds::Filing.call(feed) }
    assert_equal [ @wood ], feed.reload.sections.to_a
  end

  test "with a model configured the question goes to a job, not the request" do
    feed = @user.feeds.create!(url: "https://example.com/wood.xml")

    assert_enqueued_with(job: ClassifyFeedJob, args: [ feed ]) { Feeds::Filing.call(feed) }
    assert_empty feed.reload.sections, "the job files it; the request just gets out of the way"
  end

  # Promise 3 (docs/READER.md): the reader works identically on a box with no
  # API key. It just files by hand.
  test "with no model the feed lands in the catch-all immediately" do
    @user.household.model_profile.update!(api_key: "")
    feed = @user.feeds.create!(url: "https://example.com/wood.xml")

    assert_no_enqueued_jobs(only: ClassifyFeedJob) { Feeds::Filing.call(feed) }
    assert_equal [ Hobbies::OtherInterests.find ], feed.reload.sections.to_a
    assert_not_requested :post, LLM
  end

  test "re-filing clears the old answer and asks again, even for a filed feed" do
    feed = @user.feeds.create!(url: "https://example.com/wood.xml", sections: [ @wood ])

    assert_enqueued_with(job: ClassifyFeedJob, args: [ feed ]) { assert Feeds::Filing.refile(feed) }
    assert_empty feed.reload.sections, "otherwise the job would take it for a hand-filed feed and stop"
  end

  test "re-filing says no rather than pretending, when there is no model" do
    @user.household.model_profile.update!(api_key: "")
    feed = @user.feeds.create!(url: "https://example.com/wood.xml", sections: [ @wood ])

    assert_no_enqueued_jobs(only: ClassifyFeedJob) { assert_not Feeds::Filing.refile(feed) }
    assert_equal [ @wood ], feed.reload.sections.to_a, "and it leaves the filing it has alone"
  end
end
