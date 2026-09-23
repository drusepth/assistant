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

  test "a row re-rendered by a verb still sends its Task link back to the page it was on" do
    patch save_feed_item_path(@item), as: :turbo_stream,
      headers: { "Referer" => "http://www.example.com/reader?filter=unread" }

    assert_match CGI.escapeHTML(new_task_path(title: @item.title, section_ids: @feed.section_ids,
      return_to: "/reader?filter=unread")), response.body
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
  # The one verb a routed row needs (D-story-matching): it leaves the hobby
  # with a send-off and an Undo, like every other verb here that takes
  # something off a list — and the rejection is remembered, then shown back
  # to the model as an example.
  test "Not this takes a routed story out of the hobby and leaves a way back" do
    story, routing = routed_story

    patch reject_feed_item_path(story, section_id: routing.section_id), as: :turbo_stream

    assert_response :success
    assert_match "Not Birding", response.body
    assert_match "a rare bird turning up locally", response.body
    assert_predicate routing.reload, :rejected?
    assert_empty Feeds::River.new(users(:one), section: routing.section).scope.to_a

    patch unreject_feed_item_path(story, section_id: routing.section_id), as: :turbo_stream
    assert_not_predicate routing.reload, :rejected?
  end

  test "rejecting a routing that is already gone changes nothing" do
    story, routing = routed_story
    routing.reject!

    patch reject_feed_item_path(story, section_id: routing.section_id), as: :turbo_stream

    assert_response :success
    assert_equal 1, StoryRouting.count
  end

  test "a routed row on the hobby's own page says why the model put it there" do
    story, routing = routed_story

    get section_path(routing.section.slug)

    assert_response :success
    assert_match "Added to Birding — a rare bird turning up locally", response.body
    assert_match story.title, response.body
  end

  private
    def routed_story
      other = Hobbies::OtherInterests.find_or_create!
      birding = Hobbies::Lens.find_or_create!("Birding")
      feed = users(:one).feeds.create!(url: "https://example.com/news.xml", broad: true,
                                       sections: [ other ])
      story = feed.feed_items.create!(guid: "m1", title: "Rare warbler on the marsh")
      [ story, StoryRouting.create!(feed_item: story, section: birding,
                                    reason: "a rare bird turning up locally") ]
    end
end
