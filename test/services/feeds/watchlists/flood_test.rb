require "test_helper"

# The guard against one bad word drowning a hobby (D-story-matching §6):
# paused for the feed that flooded, not for the rule, and every bit of it
# reversible.
class Feeds::Watchlists::FloodTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @other = Hobbies::OtherInterests.find_or_create!
    @birding = Hobbies::Lens.find_or_create!("Birding")
    @news = @user.feeds.create!(url: "https://example.com/news.xml", title: "The Daily", sections: [ @other ])
    @watchlist = Watchlist.create!(user: @user, section: @birding, terms: %w[ bird ])
  end

  test "a rule that matches most of a feed is paused for that feed, by name" do
    stories(20, matching: 15)

    assert_predicate @watchlist.reload, :any_terms?
    assert @watchlist.suspended_for?(@news)
    assert_equal "bird", @watchlist.dropped.sole["term"]
    assert_equal @news.id, @watchlist.dropped.sole["feed_id"]
  end

  test "the flood it caught goes with it, but not what the user already read" do
    stories(20, matching: 15) { |item, index| item.mark_read! if index.zero? }

    assert_equal 1, FeedItemMatch.live.count, "the read one stays; the app doesn't take back spent attention"
  end

  test "a feed that is simply about the hobby is not a flood" do
    stories(20, matching: 5)

    assert_not @watchlist.reload.suspended_for?(@news)
    assert_equal 5, FeedItemMatch.live.count
  end

  test "a handful of matches is never a flood, however concentrated" do
    stories(6, matching: 6)

    assert_not @watchlist.reload.suspended_for?(@news)
  end

  test "resuming clears the notice and the rule runs over the feed again" do
    stories(20, matching: 15)
    @watchlist.resume!(@news)

    assert_not @watchlist.suspended_for?(@news)
    assert_empty @watchlist.dropped
    perform_enqueued_jobs { MatchStoriesJob.perform_later(@watchlist) }
    assert_equal 15, FeedItemMatch.live.count, "the drained matches are re-derivable, and they came back"
    assert_not @watchlist.reload.suspended_for?(@news), "and the guard doesn't overrule the decision it just lost"
  end

  test "changing the words asks the flooding question again" do
    stories(20, matching: 15)
    @watchlist.resume!(@news)
    @watchlist.add("heron")

    assert_empty @watchlist.reload.resumed_feed_ids, "new words, new question"
  end

  private
    # `matching` of `total` stories carry the word.
    def stories(total, matching:)
      items = total.times.map do |index|
        title = index < matching ? "A bird story #{index}" : "Council budget #{index}"
        @news.feed_items.create!(guid: "n#{index}", title: title)
      end
      items.each_with_index { |item, index| yield(item, index) if block_given? }
      Feeds::Match.for_feed(@news.reload, items)
    end
end
