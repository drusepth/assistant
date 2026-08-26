require "test_helper"

# What a match is *for* (D-story-matching §3.4): the story shows up in the
# hobby's river, on the hobby's card, and in its unread count — while the
# feed it came from stays exactly where it was filed.
class Feeds::MatchedRiverTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @other = Hobbies::OtherInterests.find_or_create!
    @birding = Hobbies::Lens.find_or_create!("Birding")
    @news = @user.feeds.create!(url: "https://example.com/news.xml", title: "The Daily", sections: [ @other ])
    Watchlist.create!(user: @user, section: @birding, terms: %w[ warbler ])
    @story = @news.feed_items.create!(guid: "1", title: "Rare warbler on the coast")
    @other_story = @news.feed_items.create!(guid: "2", title: "Council approves budget")
    Feeds::Match.for_feed(@news, [ @story, @other_story ])
  end

  test "the hobby's river carries the matched story, and the feed does not move" do
    river = Feeds::River.new(@user, section: @birding)

    assert_equal [ @story ], river.scope.to_a
    assert_equal 1, river.unread_count
    assert_equal [ @other ], @news.reload.sections.to_a, "matching files stories, never feeds"
  end

  # The catch-all shows the feed; the hobby shows the story. Nothing
  # disappears from where the user last saw it.
  test "the story is still in the river of the feed's own lens" do
    assert_includes Feeds::River.new(@user, section: @other).scope.to_a, @story
  end

  test "a rejected match leaves the river and does not come back" do
    @story.matches.sole.reject!

    assert_empty Feeds::River.new(@user, section: @birding).scope.to_a
  end

  test "the hobby's hub card shows the matched story and counts it once" do
    row = Hobbies::Rivers.for(@user, [ @birding ]).sole

    assert_equal [ @story ], row.items
    assert_equal 1, row.unread_count
  end

  test "a story whose feed later gains the hobby is counted once, not twice" do
    @news.sections = [ @birding ]

    row = Hobbies::Rivers.for(@user, [ @birding ]).sole

    assert_equal 2, row.unread_count, "both of the feed's stories, and neither of them twice"
  end

  # The reader's one authorization line does not move: a match lives inside
  # "a river is your own subscriptions", so it can't reach anybody else's.
  test "a match cannot show a story from a feed the viewer doesn't have" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml", sections: [ @other ])
    story = theirs.feed_items.create!(guid: "t1", title: "Their warbler story")
    FeedItemMatch.create!(feed_item: story, section: @birding)

    assert_not_includes Feeds::River.new(@user, section: @birding).scope.to_a, story
  end

  # The stranded case in full: a hobby with no feeds of its own, fed
  # entirely by stories matched out of somebody else's.
  test "a hobby with no feeds at all still gets a card, a river and a count" do
    lone = Hobbies::Lens.find_or_create!("Astronomy")
    Watchlist.create!(user: @user, section: lone, terms: %w[ eclipse ])
    story = @news.feed_items.create!(guid: "3", title: "A total eclipse over the coast")
    Feeds::Match.for_feed(@news, [ story ])

    row = Hobbies::Rivers.for(@user, [ lone ]).sole

    assert_empty row.feeds
    assert row.any_river?, "no feeds, but a river all the same"
    assert_equal [ story ], row.items
    assert_equal 1, row.unread_count
  end
end
