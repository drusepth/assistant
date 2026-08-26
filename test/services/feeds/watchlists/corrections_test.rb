require "test_helper"

# What "Not this" teaches (D-story-matching §4.3): the row is tombstoned so
# it can't come back, a word the user keeps throwing away eventually leaves
# the list, and the negatives are never written behind their back.
class Feeds::Watchlists::CorrectionsTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @other = Hobbies::OtherInterests.find_or_create!
    @birding = Hobbies::Lens.find_or_create!("Birding")
    @feed = @user.feeds.create!(url: "https://example.com/news.xml", sections: [ @other ])
    @watchlist = Watchlist.create!(user: @user, section: @birding, terms: %w[ warbler marsh ])
  end

  test "a rejection is a tombstone, so the backfill can't bring it back" do
    story = matched("Warbler Records signs a band", %w[ warbler ])

    Feeds::Watchlists::Corrections.reject!(story.matches.sole, @user)

    assert_predicate FeedItemMatch.sole, :rejected?
    perform_enqueued_jobs { MatchStoriesJob.perform_later(@watchlist) }
    assert_predicate FeedItemMatch.sole, :rejected?, "still rejected after a full re-run"
  end

  test "a word rejected three times and kept none leaves the list" do
    3.times { |n| reject(matched("Warbler Records #{n}", %w[ warbler ])) }

    assert_equal %w[ marsh ], @watchlist.reload.terms
    assert_equal "warbler", @watchlist.dropped.sole["term"]
    assert_match "you turned down 3", @watchlist.dropped.sole["detail"]
  end

  test "two rejections are not a verdict, and a word you read stays" do
    2.times { |n| reject(matched("Warbler Records #{n}", %w[ warbler ])) }
    assert_equal %w[ warbler marsh ], @watchlist.reload.terms

    3.times { |n| matched("A real warbler story #{n}", %w[ warbler ]).mark_read! }
    reject(matched("Warbler Records 3", %w[ warbler ]))

    assert_includes @watchlist.reload.terms, "warbler", "rejected three, read three — that is not a bad word"
  end

  # A negative kills every story carrying the word, and the word that fired
  # is usually the right word inside the wrong story.
  test "rejecting never writes a negative" do
    3.times { |n| reject(matched("Warbler Records #{n}", %w[ warbler ])) }

    assert_empty @watchlist.reload.negatives
  end

  test "enough corrections ask the model to write the list again — once" do
    @user.household.model_profile.update!(api_key: "test-key")

    4.times { |n| reject(matched("Warbler Records #{n}", %w[ marsh ])) }
    assert_no_enqueued_jobs only: AuthorWatchlistJob

    reject(matched("Warbler Records 5", %w[ marsh ]))
    assert_enqueued_jobs 1, only: AuthorWatchlistJob
  end

  test "with no model configured the corrections are still deterministic and silent" do
    @user.household.model_profile.update!(api_key: "")

    5.times { |n| reject(matched("Warbler Records #{n}", %w[ warbler ])) }

    assert_equal %w[ marsh ], @watchlist.reload.terms
    assert_no_enqueued_jobs only: AuthorWatchlistJob
  end

  private
    def matched(title, terms)
      item = @feed.feed_items.create!(guid: title.parameterize, title: title)
      FeedItemMatch.create!(feed_item: item, section: @birding, terms: terms)
      item
    end

    def reject(item) = Feeds::Watchlists::Corrections.reject!(item.matches.sole, @user)
end
