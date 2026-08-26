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

  test "a row read from the unread list is replaced by an undo, not by a read row" do
    patch read_feed_item_path(@item, from: "unread"), as: :turbo_stream

    assert_response :success
    assert_match "Marked read", response.body
    assert_match "Undo", response.body
    assert @item.reload.read?
  end

  test "the undo puts it back" do
    @item.mark_read!

    patch unread_feed_item_path(@item), as: :turbo_stream

    assert_not @item.reload.read?
    assert_match @item.title, response.body
  end

  test "the same row read from Everything just becomes a read row" do
    patch read_feed_item_path(@item, from: "all"), as: :turbo_stream

    assert_no_match "Marked read", response.body
    assert_match @item.title, response.body
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
  # The one verb a matched row needs (D-story-matching): it leaves the
  # hobby with a send-off and an Undo, like every other verb here that
  # takes something off a list — and the rejection is remembered.
  test "Not this takes a matched story out of the hobby and leaves a way back" do
    story, match = matched_story

    patch reject_feed_item_path(story, section_id: match.section_id), as: :turbo_stream

    assert_response :success
    assert_match "Not Birding", response.body
    assert_match "matched on warbler", response.body
    assert_predicate match.reload, :rejected?
    assert_empty Feeds::River.new(users(:one), section: match.section).scope.to_a

    patch unreject_feed_item_path(story, section_id: match.section_id), as: :turbo_stream
    assert_not_predicate match.reload, :rejected?
  end

  test "rejecting a match that is already gone changes nothing" do
    story, match = matched_story
    match.reject!

    patch reject_feed_item_path(story, section_id: match.section_id), as: :turbo_stream

    assert_response :success
    assert_equal 1, FeedItemMatch.count
  end

  test "a matched row on the hobby's own page says which words put it there" do
    story, match = matched_story

    get section_path(match.section.slug)

    assert_response :success
    assert_match "Matched on warbler", response.body
    assert_match story.title, response.body
  end

  private
    def matched_story
      other = Hobbies::OtherInterests.find_or_create!
      birding = Hobbies::Lens.find_or_create!("Birding")
      feed = users(:one).feeds.create!(url: "https://example.com/news.xml", sections: [ other ])
      story = feed.feed_items.create!(guid: "m1", title: "Rare warbler on the marsh")
      [ story, FeedItemMatch.create!(feed_item: story, section: birding, terms: %w[ warbler ]) ]
    end
end
