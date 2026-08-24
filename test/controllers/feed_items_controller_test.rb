require "test_helper"

class FeedItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @feed = users(:one).feeds.create!(url: "https://example.com/wood.xml")
    @item = @feed.feed_items.create!(guid: "1", title: "Sharpening a scraper", published_at: 1.hour.ago)
  end

  test "reading and unreading an item" do
    patch read_feed_item_path(@item)
    assert @item.reload.read?

    patch unread_feed_item_path(@item)
    assert_not @item.reload.read?
  end

  test "saving and unsaving an item" do
    patch save_feed_item_path(@item)
    assert @item.reload.saved?

    patch unsave_feed_item_path(@item)
    assert_not @item.reload.saved?
  end

  test "voting teaches this user's ranking and toggles off" do
    patch vote_feed_item_path(@item, direction: FeedItem::UP)
    assert @item.reload.upvoted?

    patch vote_feed_item_path(@item, direction: FeedItem::UP)
    assert_equal 0, @item.reload.vote
  end

  test "an action re-renders just that row over Turbo" do
    patch read_feed_item_path(@item), as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", response.media_type
    assert_match dom_id(@item), response.body
  end

  test "another member's item is untouchable" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")
      .feed_items.create!(guid: "1", title: "Bob's")

    patch read_feed_item_path(theirs)

    assert_response :not_found
    assert_not theirs.reload.read?
  end

  test "a plain (non-Turbo) action comes back to the river" do
    patch read_feed_item_path(@item), headers: { "Referer" => reader_path(filter: "all") }

    assert_redirected_to reader_path(filter: "all")
  end
end
