require "test_helper"

class ReaderControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @lens = Hobbies::Lens.find_or_create!("Woodworking")
    @feed = users(:one).feeds.create!(url: "https://example.com/wood.xml", label: "Wood", sections: [ @lens ])
    @other_feed = users(:one).feeds.create!(url: "https://example.com/misc.xml", label: "Misc")
  end

  # The titles as the page actually orders them.
  def body_titles
    Nokogiri::HTML(response.body).css("article h3").map { |node| node.text.strip }
  end

  def item(feed, title, **attributes)
    feed.feed_items.create!(
      guid: "#{feed.id}-#{title.parameterize}", title: title,
      published_at: attributes.delete(:published_at) || 1.hour.ago, **attributes
    )
  end

  test "the river is chronological across every feed, newest first" do
    item(@feed, "Five hours old", published_at: 5.hours.ago)
    item(@other_feed, "Half an hour old", published_at: 30.minutes.ago)
    item(@feed, "Two days old", published_at: 2.days.ago)

    get reader_path

    assert_response :success
    assert_equal [ "Half an hour old", "Five hours old", "Two days old" ],
      body_titles, "no ranking, no scores — the order the world published them"
  end

  test "an item with no date at all sorts by when we first saw it" do
    item(@feed, "Dated", published_at: 3.days.ago)
    undated = @feed.feed_items.create!(guid: "undated", title: "Undated", published_at: nil)

    get reader_path

    assert_equal [ "Undated", "Dated" ], body_titles
    assert_equal undated.created_at, undated.published_on
  end

  test "the hobby filter narrows to that lens's feeds" do
    item(@feed, "A woodworking bench")
    item(@other_feed, "Quarterly earnings")

    get reader_path(hobby: @lens.slug)

    assert_match "A woodworking bench", response.body
    assert_no_match "Quarterly earnings", response.body
  end

  test "read items are out of the unread river and back under Everything" do
    read = item(@feed, "Already read", read_at: Time.current)
    item(@feed, "Still unread")

    get reader_path
    assert_no_match "Already read", response.body

    get reader_path(filter: "all")
    assert_match "Already read", response.body
    assert_equal read, FeedItem.find(read.id)
  end

  test "saved keeps what you kept, read or not" do
    item(@feed, "Kept for later", saved_at: Time.current, read_at: Time.current)
    item(@feed, "Ordinary")

    get reader_path(filter: "saved")

    assert_match "Kept for later", response.body
    assert_no_match "Ordinary", response.body
  end

  test "another member's items never appear in your river" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")
    item(theirs, "Bob's private reading")

    get reader_path(filter: "all")

    assert_no_match "Bob's private reading", response.body
  end

  test "a feed filter naming someone else's feed falls back to your whole river" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")
    item(theirs, "Bob's private reading")
    item(@feed, "Mine")

    get reader_path(feed: theirs.id, filter: "all")

    assert_no_match "Bob's private reading", response.body
    assert_match "Mine", response.body
  end

  test "mark all read is scoped to the view you are looking at" do
    mine = item(@feed, "In this hobby")
    elsewhere = item(@other_feed, "Somewhere else")

    post reader_read_all_path(hobby: @lens.slug)

    assert mine.reload.read?
    assert_not elsewhere.reload.read?
  end

  test "an item can leave the river as a task, prefilled and pre-tagged" do
    item(@feed, "Build a shop-made bench hook")

    get reader_path
    assert_match CGI.escapeHTML(new_task_path(title: "Build a shop-made bench hook", section_ids: [ @lens.id ])),
      response.body

    get new_task_path(title: "Build a shop-made bench hook", section_ids: [ @lens.id ])

    assert_response :success
    assert_select "input[name='task[title]'][value=?]", "Build a shop-made bench hook"
  end

  test "an empty reader invites a first feed instead of showing an empty list" do
    users(:one).feeds.destroy_all

    get reader_path

    assert_response :success
    assert_match(/no feeds yet/i, response.body)
  end

  test "the river pages rather than rendering everything at once" do
    (Feeds::River::PER_PAGE + 3).times { |n| item(@feed, "Item #{n}", published_at: n.hours.ago) }

    get reader_path

    assert_match(/Show more/, response.body)
  end
end
