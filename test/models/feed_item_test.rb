require "test_helper"

class FeedItemTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @feed = @user.feeds.create!(url: "https://example.com/feed.xml", title: "The Wood Whisperer")
    @item = @feed.feed_items.create!(guid: "1", title: "Sharpening a scraper", published_at: 1.hour.ago)
  end

  test "one guid per feed, and the same guid may appear in two feeds" do
    other = @user.feeds.create!(url: "https://example.com/other.xml")

    assert_raises(ActiveRecord::RecordNotUnique) { @feed.feed_items.create!(guid: "1", title: "Dupe") }
    assert other.feed_items.create!(guid: "1", title: "Same id, different source")
  end

  test "saving something also marks it read — you don't keep what you haven't opened" do
    @item.save_item!

    assert @item.saved?
    assert @item.read?
  end

  test "unsaving leaves it read" do
    @item.save_item!
    @item.unsave!

    assert_not @item.saved?
    assert @item.read?
  end

  test "pressing the same arrow twice clears the vote" do
    @item.vote!(FeedItem::UP)
    assert @item.upvoted?

    @item.vote!(FeedItem::UP)
    assert_equal 0, @item.vote

    @item.vote!(FeedItem::DOWN)
    assert @item.downvoted?
  end

  test "a nonsense vote direction is clamped rather than stored" do
    @item.vote!(99)

    assert_equal FeedItem::UP, @item.vote
  end

  test "the blurb is plain text, squished and capped" do
    @item.update!(summary: "A burnisher   and\nfive minutes. " + ("x" * 500))

    assert_not_includes @item.blurb, "\n"
    assert_operator @item.blurb.length, :<=, 320
  end

  test "an undated item still sorts, by when we first saw it" do
    undated = @feed.feed_items.create!(guid: "2", title: "Undated")

    assert_equal undated.created_at, undated.published_on
  end

  test "the source name is the feed's" do
    assert_equal "The Wood Whisperer", @item.source_name
  end
end
