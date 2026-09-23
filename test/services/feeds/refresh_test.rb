require "test_helper"

class Feeds::RefreshTest < ActiveJob::TestCase
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

  # A worker killed mid-fetch never reaches the success or failure write, so
  # the attempt itself has to have moved the feed out of the next sweep.
  test "a check that never finishes still counts, so the sweep backs off" do
    stub_request(:get, @feed.url).to_raise(NoMemoryError)

    assert_raises(NoMemoryError) { Feeds::Refresh.call(@feed) }

    @feed.reload
    assert_equal Feed::INTERRUPTED, @feed.last_error
    assert_equal 1, @feed.failure_count
    assert_not @feed.due_for_refresh?
  end

  test "a failed check is counted once, with its own reason" do
    stub_request(:get, @feed.url).to_return(status: 500)

    Feeds::Refresh.call(@feed)

    assert_equal 1, @feed.reload.failure_count
    assert_equal "the site answered HTTP 500", @feed.last_error
  end

  test "a recovered feed clears its error and its backoff" do
    @feed.record_failure!("the site answered HTTP 500")
    stub_feed(item(title: "Back online"))

    Feeds::Refresh.call(@feed)

    assert @feed.reload.healthy?
    assert_equal 0, @feed.failure_count
  end

  test "the river is in the publisher's order, oldest entry to newest" do
    stub_feed([ item(title: "Older", date: 3.days.ago), item(title: "Newer", date: 1.hour.ago) ].join)

    Feeds::Refresh.call(@feed)

    assert_equal [ "Newer", "Older" ], @feed.feed_items.newest.map(&:title)
  end

  test "the validators the publisher sent are kept, and sent back next time" do
    stub_request(:get, @feed.url).to_return(
      body: "<rss><channel><title>T</title><item><title>One</title><link>https://e.com/1</link></item></channel></rss>",
      headers: { "Content-Type" => "application/rss+xml", "ETag" => "W/\"abc\"",
                 "Last-Modified" => "Tue, 18 Aug 2026 09:00:00 GMT" }
    )
    Feeds::Refresh.call(@feed)

    assert_equal "W/\"abc\"", @feed.reload.etag
    assert_equal "Tue, 18 Aug 2026 09:00:00 GMT", @feed.last_modified

    conditional = stub_request(:get, @feed.url)
      .with(headers: { "If-None-Match" => "W/\"abc\"",
                       "If-Modified-Since" => "Tue, 18 Aug 2026 09:00:00 GMT" })
      .to_return(status: 304)

    result = Feeds::Refresh.call(@feed)

    assert_requested conditional
    assert result.ok?
    assert_not result.changed?, "a 304 is a successful check with nothing to do"
    assert @feed.reload.healthy?
    assert_equal 1, @feed.feed_items.count, "nothing was parsed and nothing was lost"
  end

  test "a feed that stops sending validators stops being asked with them" do
    stub_request(:get, @feed.url).to_return(
      body: "<rss><channel><title>T</title></channel></rss>",
      headers: { "Content-Type" => "application/rss+xml", "ETag" => "\"one\"" }
    )
    Feeds::Refresh.call(@feed)
    assert_equal "\"one\"", @feed.reload.etag

    stub_request(:get, @feed.url).to_return(
      body: "<rss><channel><title>T</title></channel></rss>",
      headers: { "Content-Type" => "application/rss+xml" }
    )
    Feeds::Refresh.call(@feed)

    assert_nil @feed.reload.etag
    assert_empty @feed.conditional_headers
  end

  test "reading an item stamps its feed, which is what keeps the poll polite" do
    stub_feed(item(title: "One"))
    Feeds::Refresh.call(@feed)

    assert_nil @feed.reload.last_read_at
    @feed.feed_items.sole.mark_read!

    assert_not_nil @feed.reload.last_read_at
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

  # Routing rides the refresh (D-story-matching), but only as far as the
  # queue: reading the stories is a model call, and a publisher's poll has
  # no business waiting on a provider.
  test "a broad feed's new stories send the router to work; a focused one doesn't" do
    Hobbies::Lens.find_or_create!("Birding")
    @feed.update!(broad: true, sections: [ Hobbies::OtherInterests.find_or_create! ])
    stub_feed(item(title: "Rare warbler on the marsh"))

    assert_enqueued_with(job: RouteStoriesJob) { Feeds::Refresh.call(@feed) }
    assert_equal [ Hobbies::OtherInterests.find ], @feed.reload.sections.to_a, "the feed itself never moves"

    @feed.update!(broad: false)
    @feed.feed_items.destroy_all
    assert_no_enqueued_jobs(only: RouteStoriesJob) { Feeds::Refresh.call(@feed) }
  end
end
