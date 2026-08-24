require "test_helper"

class Feeds::RankTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @feed = @user.feeds.create!(url: "https://example.com/feed.xml")
  end

  def item(title, published_at:, relevance: 0.0, **attributes)
    @feed.feed_items.create!(
      guid: "#{title}-#{published_at.to_i}", title: title,
      published_at: published_at, relevance: relevance, **attributes
    )
  end

  test "a strong match outranks a fresher item it is not much older than" do
    fresh = item("Anything at all", published_at: 1.hour.ago, relevance: 0.0)
    match = item("A woodworking bench", published_at: 5.hours.ago, relevance: 0.9)

    assert_equal [ match, fresh ], Feeds::Rank.sort([ fresh, match ])
  end

  test "a match does not buy a permanent seat at the top" do
    fresh = item("Anything at all", published_at: 1.hour.ago, relevance: 0.0)
    stale_match = item("A woodworking bench", published_at: 4.days.ago, relevance: 1.0)

    assert_equal [ fresh, stale_match ], Feeds::Rank.sort([ stale_match, fresh ])
  end

  test "what the user downvoted sinks below its neighbours, and is still there" do
    ordinary = item("Ordinary", published_at: 6.hours.ago, relevance: 0.0)
    disliked = item("Crypto again", published_at: 1.minute.ago, relevance: -1.0)

    ranked = Feeds::Rank.sort([ disliked, ordinary ])

    assert_equal [ ordinary, disliked ], ranked
    assert_includes ranked, disliked, "a downvote sinks an item; it never hides it"
  end

  test "ties break by recency, so the order does not shuffle between page loads" do
    older = item("A", published_at: 3.hours.ago)
    newer = item("B", published_at: 2.hours.ago)

    assert_equal [ newer, older ], Feeds::Rank.sort([ older, newer ])
    assert_equal [ newer, older ], Feeds::Rank.sort([ newer, older ])
  end

  test "an item published in the future is treated as new, not as newer than everything" do
    future = item("Scheduled early", published_at: 2.days.from_now)
    now = item("Just posted", published_at: 1.minute.ago)

    assert_in_delta Feeds::Rank.score(now), Feeds::Rank.score(future), 0.1
  end

  test "a saved item is worth a few hours, not a pin" do
    saved = item("Kept for later", published_at: 8.hours.ago, saved_at: Time.current, read_at: Time.current)
    fresh = item("Just posted", published_at: 1.minute.ago)

    assert_operator Feeds::Rank.score(saved), :<, Feeds::Rank.score(fresh)
    assert_operator Feeds::Rank.score(saved), :>,
      Feeds::Rank.score(item("Unsaved twin", published_at: 8.hours.ago))
  end
end
