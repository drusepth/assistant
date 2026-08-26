require "test_helper"

# A rule is tested against the river before it ships (D-story-matching §4.1).
class Feeds::Watchlists::CorpusTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @feed = @user.feeds.create!(url: "https://example.com/news.xml")
    50.times { |n| @feed.feed_items.create!(guid: "n#{n}", title: "Nature notes number #{n}") }
    5.times { |n| @feed.feed_items.create!(guid: "w#{n}", title: "Warbler count #{n}") }
  end

  test "a word that describes the river rather than the hobby is dropped, with the number" do
    verdict = Feeds::Watchlists::Corpus.new(@user).test(%w[ warbler nature ])

    assert_equal %w[ warbler ], verdict.kept
    assert_equal "nature", verdict.dropped.sole["term"]
    assert_match(/matched \d+% of your river/, verdict.dropped.sole["detail"])
  end

  # A brand-new instance has nothing to judge against, and three stories
  # should not be allowed to gut the first rule anybody writes.
  test "under enough material the test says nothing and keeps everything" do
    empty = users(:two)

    assert_not_predicate Feeds::Watchlists::Corpus.new(empty), :enough?
    assert_equal %w[ nature ], Feeds::Watchlists::Corpus.new(empty).test(%w[ nature ]).kept
  end
end
