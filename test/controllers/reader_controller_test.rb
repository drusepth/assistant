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

  # The face is a view concern, so it is asked of the helper the way the row
  # asks for it.
  def helper_face(feed) = ApplicationController.helpers.feed_face(feed).to_s[/bg-[\w-]+/]
  def helper_monogram(feed) = ApplicationController.helpers.feed_monogram(feed)

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

  # Two urls, because a row has two ways of becoming read and they mean
  # different things (D-reader-density): opening it *here* keeps it in the
  # unread list, and going to the source takes it out.
  test "the row carries both of the ways it can be opened" do
    item = item(@feed, "Sharpening a card scraper", url: "https://example.com/scraper")

    get reader_path

    row = Nokogiri::HTML(response.body).css("##{ActionView::RecordIdentifier.dom_id(item)}").first
    assert_equal "reader-row", row["data-controller"]
    assert_equal read_feed_item_path(item, from: "expand"), row["data-reader-row-read-url-value"]
    assert_equal read_feed_item_path(item, from: "unread"), row["data-reader-row-dismiss-url-value"]
    assert_equal "reader-row#openOrExpand", row.css("h3 a").first["data-action"]
  end

  test "opening a row in place leaves it in the unread list, read and open" do
    item = item(@feed, "Sharpening a card scraper")

    patch read_feed_item_path(item, from: "expand"), as: :turbo_stream

    assert_predicate item.reload, :read?
    assert_match(/is-open/, response.body)
    assert_no_match(/Marked read —/, response.body)
  end

  test "a row marked read from the unread list still gets its send-off" do
    item = item(@feed, "Sharpening a card scraper")

    patch read_feed_item_path(item, from: "unread"), as: :turbo_stream

    assert_match(/Marked read —/, response.body)
  end

  test "an empty reader invites a first feed instead of showing an empty list" do
    users(:one).feeds.destroy_all

    get reader_path

    assert_response :success
    assert_match(/no feeds yet/i, response.body)
  end

  # No JS suite in this repo, so the assertion is the wiring — the same
  # convention the mark-read-on-open controller has had since it shipped.
  test "the river is wired for the keyboard, rows and all" do
    item(@feed, "Bench hooks")

    get reader_path

    page = Nokogiri::HTML(response.body)
    list = page.at_css("[data-controller~=river]")
    assert list, "j/k/o/m/s need a scope to run in"
    assert list.css("[data-river-target=row]").any?
    assert list.at_css("[data-river-target=sheet]"), "`?` needs a sheet to open"
    assert_match(/all keys/, page.at_css("kbd").parent.text)
  end

  # The verbs a key presses by name have to exist under that name, or `m`
  # and `s` press nothing (river_controller.js).
  test "every key that presses a verb has a verb to press" do
    item(@feed, "Bench hooks")

    get reader_path

    page = Nokogiri::HTML(response.body)
    labels = page.css("[data-river-target=row] button").map { |button| button.text.strip }
    assert_includes labels, "Read"
    assert_includes labels, "Save"
    assert page.at_css("[data-river-refresh]"), "`r` presses Check now"
    assert page.at_css("[data-river-read-all]"), "`A` presses Mark all read"
  end

  # ---- density (D-reader-density) ----------------------------------------

  # The chip that used to be on every row. "Other Interests" is the catch-all
  # every feed has by construction (D-hobby-feeds), so painting it made a
  # label that appeared on 100% of items and carried no bits — while being
  # the highest-contrast thing in the row.
  test "the catch-all lens never earns a chip" do
    @other_feed.sections = [ Hobbies::OtherInterests.find_or_create! ]
    item(@other_feed, "Parrot eggs")

    get reader_path

    assert_match "Parrot eggs", response.body
    assert_no_match Hobbies::OtherInterests::NAME, Nokogiri::HTML(response.body).css(".reader-signal").to_s
  end

  test "the lens you have already filtered to never earns a chip either" do
    item(@feed, "A woodworking bench")

    get reader_path
    assert_match @lens.name, Nokogiri::HTML(response.body).css(".reader-signal").to_s

    get reader_path(hobby: @lens.slug)
    assert_no_match @lens.name, Nokogiri::HTML(response.body).css(".reader-signal").to_s
  end

  test "a feed's face is stable, and two feeds on one host wear the same one" do
    one = users(:one).feeds.create!(url: "https://feeds.example.org/a.xml")
    two = users(:one).feeds.create!(url: "https://example.org/b.xml")

    assert_equal helper_face(one), helper_face(two), "same publisher, same face"
    assert_equal "E", helper_monogram(one), "the noise subdomain is not the name"
    assert_equal helper_face(one), helper_face(one.reload), "and it never moves"
  end

  test "the river is grouped under a day spine" do
    # A fixed clock, because the spine's whole job is naming the day: for the
    # two hours after local midnight "2 hours ago" is yesterday, and the
    # assertion below would be wrong about the code rather than the code
    # being wrong. A Thursday midday, so "3 days ago" is a plain weekday.
    travel_to Time.zone.local(2026, 8, 27, 12)
    item(@feed, "Today's", published_at: 2.hours.ago)
    item(@feed, "Older", published_at: 3.days.ago)

    get reader_path

    days = Nokogiri::HTML(response.body).css(".reader-day").map { |node| node.text.strip }
    assert_includes days, "Earlier today"
    assert_equal 2, days.length, "one heading per day, not one per row"
  end

  # A CSS invariant, asserted here because it is the only suite there is and
  # the failure was invisible on a laptop: any `overflow` other than visible
  # makes the river the *scroll container* for the sticky day headers inside
  # it, so they pin to `top: var(--app-header-h)` measured from the river's
  # own top edge — which never scrolls. On a phone that token is 3.5rem, so
  # the first heading sat permanently 56px into the list, on top of the first
  # row. On a laptop the token is 0, which is exactly where the heading
  # belongs anyway, so nothing looked wrong there.
  test "the river is not a scroll container, or the day spine pins inside it" do
    item(@feed, "Bench hooks")

    get reader_path

    classes = Nokogiri::HTML(response.body).at_css(".reader-river")["class"]
    assert_no_match(/overflow-(hidden|auto|scroll|clip)/, classes,
      "sticky headings inside this element would pin to it rather than to the page")
  end

  test "saved is a shelf and unread is a river" do
    item(@feed, "Kept", saved_at: Time.current, read_at: Time.current)

    get reader_path(filter: "saved")
    assert_select ".reader-shelf"
    assert_select ".reader-river", false

    get reader_path
    assert_select ".reader-river", false, "nothing unread, so no river"
  end

  test "the scope tree lists feeds under the hobby they were filed under" do
    item(@feed, "A woodworking bench")

    get reader_path

    lens_row = Nokogiri::HTML(response.body).at_css(".reader-scope-group")
    assert_match @lens.name, lens_row.text
    assert_match "Wood", lens_row.text, "the feed rides under its lens, not in a flat list"
  end

  # ---- read-on-scroll -----------------------------------------------------

  test "a batch of scrolled-past items is marked read in one request" do
    one = item(@feed, "One")
    two = item(@feed, "Two")

    post reader_read_seen_path, params: { ids: [ one.id, two.id ] }

    assert_response :success
    assert_predicate one.reload, :read?
    assert_predicate two.reload, :read?
    assert_not_nil @feed.reload.last_read_at, "the batch still stamps the feed, so polling stays polite"
  end

  test "undoing a batch puts every one of them back" do
    one = item(@feed, "One", read_at: Time.current)

    post reader_unread_seen_path, params: { ids: [ one.id ] }

    assert_not_predicate one.reload, :read?
  end

  test "a batch cannot reach another member's items" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")
    hers = item(theirs, "Bob's private reading")
    mine = item(@feed, "Mine")

    post reader_read_seen_path, params: { ids: [ hers.id, mine.id ] }

    assert_response :success
    assert_not_predicate hers.reload, :read?, "a forged id in the list updates nothing"
    assert_predicate mine.reload, :read?, "and the rest of the batch still goes through"
  end

  test "the river pages rather than rendering everything at once" do
    (Feeds::River::PER_PAGE + 3).times { |n| item(@feed, "Item #{n}", published_at: n.hours.ago) }

    get reader_path

    assert_match(/Older/, response.body)
  end
end
