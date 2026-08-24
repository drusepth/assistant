require "test_helper"

class Feeds::RefreshTest < ActiveSupport::TestCase
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  setup do
    Web::Fetch.resolver = PUBLIC_DNS
    @user = users(:one)
    @feed = @user.feeds.create!(url: "https://example.com/feed.xml")
  end

  teardown { Web::Fetch.resolver = Resolv }

  def stub_feed(items, title: "The Wood Whisperer")
    body = <<~XML
      <rss><channel><title>#{title}</title><link>https://example.com</link>
        #{items}
      </channel></rss>
    XML
    stub_request(:get, @feed.url).to_return(body: body, headers: { "Content-Type" => "application/rss+xml" })
  end

  def item(title:, guid: nil, link: "https://example.com/#{title.parameterize}", date: nil)
    <<~XML
      <item>
        <title>#{title}</title><link>#{link}</link>
        #{"<guid>#{guid}</guid>" if guid}
        #{"<pubDate>#{date.httpdate}</pubDate>" if date}
      </item>
    XML
  end

  test "a first fetch fills the river and names the feed" do
    stub_feed(item(title: "Sharpening a scraper", date: 2.hours.ago))

    result = Feeds::Refresh.call(@feed)

    assert result.ok?
    assert_equal 1, result.added
    assert_equal "The Wood Whisperer", @feed.reload.title
    assert_equal "https://example.com", @feed.site_url
    assert_equal "Sharpening a scraper", @feed.feed_items.sole.title
    assert @feed.last_fetched_at
  end

  test "re-fetching the same entries adds nothing and keeps read state" do
    stub_feed(item(title: "Sharpening a scraper", guid: "abc"))
    Feeds::Refresh.call(@feed)
    @feed.feed_items.sole.mark_read!

    result = Feeds::Refresh.call(@feed)

    assert_equal 0, result.added
    assert_equal 1, @feed.feed_items.count
    assert @feed.feed_items.sole.read?, "a re-listed item does not come back unread"
  end

  test "a corrected headline updates in place without disturbing the reader's state" do
    stub_feed(item(title: "Sharpenin a scraper", guid: "abc"))
    Feeds::Refresh.call(@feed)
    @feed.feed_items.sole.save_item!

    stub_feed(item(title: "Sharpening a scraper", guid: "abc"))
    result = Feeds::Refresh.call(@feed)

    stored = @feed.feed_items.sole
    assert_equal 1, result.updated
    assert_equal "Sharpening a scraper", stored.title
    assert stored.saved?, "saving is the reader's, not the publisher's"
  end

  test "a fetch failure lands on the feed's row instead of raising" do
    stub_request(:get, @feed.url).to_return(status: 404)

    result = Feeds::Refresh.call(@feed)

    assert_not result.ok?
    assert_equal 1, @feed.reload.failure_count
    assert_match(/404/, @feed.last_error)
    assert_not @feed.healthy?
  end

  test "a feed that turns into a web page is reported, not silently emptied" do
    stub_request(:get, @feed.url).to_return(body: "<html>gone</html>", headers: { "Content-Type" => "text/html" })
    @feed.feed_items.create!(guid: "kept", title: "Still here")

    result = Feeds::Refresh.call(@feed)

    assert_not result.ok?
    assert_equal 1, @feed.feed_items.count
  end

  test "a recovered feed clears its error and its backoff" do
    @feed.record_failure!("the site answered HTTP 500")
    stub_feed(item(title: "Back online"))

    Feeds::Refresh.call(@feed)

    assert @feed.reload.healthy?
    assert_equal 0, @feed.failure_count
  end

  test "items are scored against the user's hobbies at ingest" do
    Hobbies::Lens.find_or_create!("Woodworking")
    @feed.sections = [ Hobbies::Lens.named("Woodworking") ]
    stub_feed(item(title: "A woodworking bench for small shops"))

    Feeds::Refresh.call(@feed)

    assert_operator @feed.feed_items.sole.relevance, :>, 0.5
  end

  test "an entry's image only survives if it is an http(s) address" do
    stub_request(:get, @feed.url).to_return(
      headers: { "Content-Type" => "application/rss+xml" },
      body: <<~XML
        <rss><channel><title>T</title>
          <item><title>One</title><link>https://example.com/1</link>
            <enclosure url="javascript:alert(1)" type="image/png"/></item>
        </channel></rss>
      XML
    )

    Feeds::Refresh.call(@feed)

    assert_nil @feed.feed_items.sole.image_url
  end

  test "read items past the cap are pruned; saved and unread ones never are" do
    old = 400.days.ago
    saved = @feed.feed_items.create!(guid: "saved", title: "Kept", published_at: old,
      read_at: Time.current, saved_at: Time.current)
    unread = @feed.feed_items.create!(guid: "unread", title: "Never opened", published_at: old)
    doomed = (1..3).map do |n|
      @feed.feed_items.create!(guid: "old-#{n}", title: "Old #{n}", published_at: old + n.minutes,
        read_at: Time.current)
    end
    keeper = @feed.feed_items.create!(guid: "recent", title: "Recent", published_at: 1.hour.ago, read_at: Time.current)

    stub_feed(item(title: "Fresh one"))
    Feeds::Refresh.call(@feed, keep: 2)

    assert FeedItem.exists?(saved.id), "a saved item is never pruned"
    assert FeedItem.exists?(unread.id), "unread is mail nobody opened, not archive"
    assert FeedItem.exists?(keeper.id)
    assert_not FeedItem.exists?(doomed.first.id), "the oldest read items go first"
  end
end
