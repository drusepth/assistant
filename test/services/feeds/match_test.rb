require "test_helper"

# The rule, applied (D-story-matching §3.2): a term in the title, or two
# distinct terms anywhere, and no negative — offline, at ingest, for free.
class Feeds::MatchTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @other = Hobbies::OtherInterests.find_or_create!
    @birding = Hobbies::Lens.find_or_create!("Birding")
    @news = @user.feeds.create!(url: "https://example.com/news.xml", title: "The Daily", sections: [ @other ])
  end

  test "a term in the headline is enough, and one mention in the body is not" do
    watch %w[ warbler ]
    headline = item("Rare warbler spotted on the coast")
    passing = item("Council budget approved", summary: "The chair, a keen warbler enthusiast, spoke.")

    match([ headline, passing ])

    assert_equal [ @birding ], headline.reload.matched_sections.to_a
    assert_empty passing.reload.matched_sections
  end

  test "two distinct terms in the body carry a story a headline didn't" do
    watch %w[ warbler ebird ]
    story = item("A morning on the marsh", summary: "We logged the warbler on ebird before lunch.")

    match([ story ])

    assert_equal [ @birding ], story.reload.matched_sections.to_a
    assert_equal %w[ warbler ebird ], story.matches.sole.terms, "the row remembers why it is here"
  end

  test "the same term twice is still one term" do
    watch %w[ warbler ebird ]
    story = item("A morning on the marsh", summary: "A warbler, and then another warbler.")

    match([ story ])

    assert_empty story.reload.matched_sections
  end

  test "a negative anywhere kills the match" do
    watch %w[ warbler ], negatives: %w[ records ]
    story = item("Warbler Records signs a new band")

    match([ story ])

    assert_empty story.reload.matched_sections
  end

  test "terms match whole words, not fragments" do
    watch %w[ bass ]
    inside = item("Bassoon lessons for beginners")
    whole = item("Bass fishing in the delta")

    match([ inside, whole ])

    assert_empty inside.reload.matched_sections, "'bass' is not in 'bassoon'"
    assert_equal [ @birding ], whole.reload.matched_sections.to_a
  end

  test "case and accents fold, and a phrase matches as a phrase" do
    watch [ "creme brulee" ]
    story = item("Crème Brûlée, three ways")

    match([ story ])

    assert_equal [ @birding ], story.reload.matched_sections.to_a
  end

  # A word boundary between two kanji is not a place, so a script that
  # doesn't space its words gets substring matching instead.
  test "a term in a script without word boundaries matches inside a run" do
    watch [ "野鳥" ]
    story = item("今朝の野鳥観察の記録", guid: "jp-1")

    match([ story ])

    assert_equal [ @birding ], story.reload.matched_sections.to_a
  end

  test "a feed already filed under the hobby is never matched into it again" do
    watch %w[ warbler ]
    @news.sections = [ @birding ]
    story = item("Rare warbler spotted")

    match([ story ])

    assert_empty FeedItemMatch.all, "that story is already in that river; a row saying so is a duplicate"
  end

  test "a match never overwrites a row that already exists, rejected or filed by hand" do
    watch %w[ warbler ]
    story = item("Rare warbler spotted")
    match([ story ])
    story.matches.sole.reject!

    match([ story ])

    assert_equal 1, story.reload.feed_item_matches.count
    assert_predicate FeedItemMatch.sole, :rejected?, "a rejection is remembered, not re-run"
  end

  test "a rule with no terms, or one paused for this feed, matches nothing" do
    watchlist = watch([])
    match([ item("Rare warbler spotted") ])
    assert_empty FeedItemMatch.all

    watchlist.update!(terms: %w[ warbler ])
    watchlist.suspend!(@news, reason: "warbler")
    match([ item("Another warbler", guid: "two") ])
    assert_empty FeedItemMatch.all
  end

  # Feeds are one user's; so is everything a rule does with them.
  test "one household member's rule never touches another's stories" do
    watch %w[ warbler ]
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml", sections: [ @other ])
    story = theirs.feed_items.create!(guid: "t1", title: "Rare warbler spotted")

    Feeds::Match.for_feed(theirs, [ story ])

    assert_empty story.reload.matched_sections
  end

  private
    def watch(terms, negatives: [], section: @birding)
      Watchlist.create!(user: @user, section: section, terms: terms, negatives: negatives)
    end

    def item(title, summary: nil, guid: nil, feed: @news)
      feed.feed_items.create!(guid: guid || title.parameterize, title: title, summary: summary)
    end

    def match(items, feed: @news) = Feeds::Match.for_feed(feed.reload, items)
end
