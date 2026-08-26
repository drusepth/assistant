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

  # The Hobbies row in the rail, which is where the unread pile rides now.
  def hobbies_rail_link(page)
    page.css("aside a[href='#{section_path("hobbies")}']").first
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

  # The reader is no longer a rail destination of its own (D-hobby-feeds):
  # the river is what makes Hobbies different every day, so the pile rides
  # that row.
  test "the rail carries the unread count on Hobbies, and has no Reader row" do
    item(@feed, "Unread one")
    item(@feed, "Unread two")
    item(@feed, "Already read", read_at: Time.current)

    get reader_path

    page = Nokogiri::HTML(response.body)
    assert_empty page.css("a[href='#{reader_path}']").select { |link| link.ancestors("aside").any? },
      "the reader is reached from the hub now, not from a rail row"
    assert_equal "2", hobbies_rail_link(page).text.scan(/\d+/).last,
      "the pile behind the row is the reason to open it"
  end

  test "a paused feed's unread items are not counted in the rail" do
    item(@feed, "Unread one")
    @feed.update!(active: false)

    get reader_path

    assert_no_match(/\d/, hobbies_rail_link(Nokogiri::HTML(response.body)).text)
  end

  test "marking everything read stamps the feeds, so the polling stays polite" do
    item(@feed, "One")

    post reader_read_all_path

    assert_not_nil @feed.reload.last_read_at
  end

  test "the row carries what opening the article should call" do
    item = item(@feed, "Sharpening a card scraper", url: "https://example.com/scraper")

    get reader_path

    row = Nokogiri::HTML(response.body).css("##{ActionView::RecordIdentifier.dom_id(item)}").first
    assert_equal "reader", row["data-controller"]
    assert_equal read_feed_item_path(item, from: "unread"), row["data-reader-url-value"]
    assert_equal "reader#markRead", row.css("h3 a").first["data-action"]
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

    assert_match(/Older/, response.body)
  end
end
