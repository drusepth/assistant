require "test_helper"

# The job that files a feed (D-hobby-feeds). Every path ends with the feed
# having a home, because the invariant the hub rests on is that every feed
# has a hobby or has Other Interests.
class ClassifyFeedJobTest < ActiveJob::TestCase
  LLM = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @wood = Hobbies::Lens.find_or_create!("Woodworking")
    @feed = @user.feeds.create!(url: "https://example.com/wood.xml", title: "The Wood Whisperer")
  end

  test "the model's pick becomes the feed's lenses, and the run is stamped" do
    stub_answer([ "woodworking" ])

    ClassifyFeedJob.perform_now(@feed)

    assert_equal [ @wood ], @feed.reload.sections.to_a
    assert @feed.classified?
  end

  test "an empty answer is an answer: the feed lands in the catch-all, stamped" do
    stub_answer([])

    ClassifyFeedJob.perform_now(@feed)

    assert_equal [ Hobbies::OtherInterests.find ], @feed.reload.sections.to_a
    assert @feed.classified?, "the model looked and chose nothing — that is not the same as never looking"
  end

  test "a feed filed by hand while the job waited is left alone" do
    @feed.sections = [ @wood ]

    ClassifyFeedJob.perform_now(@feed)

    assert_not_requested :post, LLM
    assert_not @feed.reload.classified?
  end

  test "a model that keeps failing still leaves the feed with a home" do
    stub_request(:post, LLM).to_return(status: 401, body: "nope")

    assert_difference "AppError.count", 1 do
      ClassifyFeedJob.perform_now(@feed)
    end

    assert_equal [ Hobbies::OtherInterests.find ], @feed.reload.sections.to_a
    assert_not @feed.classified?, "blank means Re-file can try again later"
  end

  # A 429 is "not now", not "not ever": the job goes back on the queue rather
  # than filing the feed on a failure it can still recover from.
  test "a transient failure is retried rather than written off" do
    stub_request(:post, LLM).to_return(status: 429, body: "slow down")

    assert_enqueued_with(job: ClassifyFeedJob) do
      assert_no_difference("AppError.count") { ClassifyFeedJob.perform_now(@feed) }
    end
    assert_empty @feed.reload.sections
  end

  private
    def stub_answer(slugs)
      stub_request(:post, LLM).to_return(
        status: 200,
        body: { choices: [ { message: { content: { hobbies: slugs }.to_json } } ] }.to_json
      )
    end
end
