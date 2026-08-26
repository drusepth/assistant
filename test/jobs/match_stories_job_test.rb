require "test_helper"

# What a rule change means for the stories already in the box
# (D-story-matching §3.2) — bounded to the window a reader reads, and
# careful about what it is allowed to throw away.
class MatchStoriesJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @other = Hobbies::OtherInterests.find_or_create!
    @birding = Hobbies::Lens.find_or_create!("Birding")
    @news = @user.feeds.create!(url: "https://example.com/news.xml", sections: [ @other ])
    @watchlist = Watchlist.create!(user: @user, section: @birding, terms: %w[ warbler ])
  end

  test "a new word reaches back over the stories already here" do
    story = item("Rare warbler on the marsh")

    MatchStoriesJob.perform_now(@watchlist)

    assert_equal [ @birding ], story.reload.matched_sections.to_a
  end

  test "a word taken out takes its rows with it" do
    story = item("Rare warbler on the marsh")
    MatchStoriesJob.perform_now(@watchlist)

    @watchlist.update!(terms: [])
    MatchStoriesJob.perform_now(@watchlist)

    assert_empty story.reload.matched_sections
  end

  test "a rejection and a hand-filed row both survive the rebuild" do
    rejected = item("Warbler Records signs a band")
    FeedItemMatch.create!(feed_item: rejected, section: @birding, rejected_at: Time.current)
    by_hand = item("A story I filed myself", title_matches: false)
    FeedItemMatch.create!(feed_item: by_hand, section: @birding, source: :hand)

    MatchStoriesJob.perform_now(@watchlist)

    assert_predicate FeedItemMatch.find_by(feed_item: rejected), :rejected?
    assert FeedItemMatch.find_by(feed_item: by_hand), "a rule never overwrites a human"
  end

  test "the backfill looks at the window a reader reads, not at the archive" do
    old = item("An ancient warbler")
    old.update!(published_at: 90.days.ago)

    MatchStoriesJob.perform_now(@watchlist)

    assert_empty old.reload.matched_sections
  end

  test "a feed already filed under the hobby is left alone" do
    @news.sections = [ @birding ]
    story = item("Rare warbler on the marsh")

    MatchStoriesJob.perform_now(@watchlist)

    assert_empty FeedItemMatch.all
    assert_includes Feeds::River.new(@user, section: @birding).scope.to_a, story
  end

  private
    def item(title, title_matches: true)
      @news.feed_items.create!(guid: title.parameterize, title: title_matches ? title : "Plain #{title}")
    end
end
