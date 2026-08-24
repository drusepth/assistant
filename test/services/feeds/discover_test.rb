require "test_helper"

class Feeds::DiscoverTest < ActiveSupport::TestCase
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  setup { Web::Fetch.resolver = PUBLIC_DNS }
  teardown { Web::Fetch.resolver = Resolv }

  FEED = <<~XML.freeze
    <rss><channel><title>The Wood Whisperer</title><link>https://example.com</link>
      <item><title>Scrapers</title><link>https://example.com/1</link></item>
    </channel></rss>
  XML

  test "a pasted feed address is used as-is" do
    stub_request(:get, "https://example.com/feed.xml")
      .to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    found = Feeds::Discover.call("https://example.com/feed.xml")

    assert_equal "https://example.com/feed.xml", found.url
    assert_equal "The Wood Whisperer", found.parsed.title
  end

  test "a pasted site is resolved through its autodiscovery tag" do
    page = <<~HTML
      <html><head>
        <link rel="alternate" type="application/rss+xml" href="/posts.xml">
      </head><body>A blog</body></html>
    HTML
    stub_request(:get, "https://example.com/blog").to_return(body: page, headers: { "Content-Type" => "text/html" })
    stub_request(:get, "https://example.com/posts.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    found = Feeds::Discover.call("example.com/blog")

    assert_equal "https://example.com/posts.xml", found.url, "a relative href resolves against the page"
  end

  test "a site with no tags is guessed at the conventional paths" do
    stub_request(:get, "https://example.com").to_return(body: "<html><body>hi</body></html>", headers: { "Content-Type" => "text/html" })
    stub_request(:get, "https://example.com/feed").to_return(status: 404)
    stub_request(:get, "https://example.com/feed.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    assert_equal "https://example.com/feed.xml", Feeds::Discover.call("https://example.com").url
  end

  test "a subreddit becomes its own feed without a fetch to work it out" do
    stub_request(:get, "https://www.reddit.com/r/woodworking/.rss")
      .to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    assert_equal "https://www.reddit.com/r/woodworking/.rss",
      Feeds::Discover.call("https://www.reddit.com/r/woodworking").url
  end

  test "a YouTube channel becomes the channel feed" do
    stub_request(:get, "https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
      .to_return(body: FEED, headers: { "Content-Type" => "application/atom+xml" })

    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      Feeds::Discover.call("youtube.com/channel/UC123").url
  end

  test "a page with no feed anywhere says so" do
    stub_request(:get, %r{https://example\.com}).to_return(body: "<html>nothing here</html>", headers: { "Content-Type" => "text/html" })

    error = assert_raises(Feeds::Discover::Error) { Feeds::Discover.call("https://example.com") }
    assert_match(/no feed found/i, error.message)
  end

  test "an unreachable site explains itself rather than blaming the feed" do
    stub_request(:get, %r{https://example\.com}).to_return(status: 500)

    error = assert_raises(Feeds::Discover::Error) { Feeds::Discover.call("https://example.com") }
    assert_match(/couldn't read/i, error.message)
  end

  test "non-http schemes and empty pastes never reach the fetcher" do
    assert_raises(Feeds::Discover::Error) { Feeds::Discover.call("javascript:alert(1)") }
    assert_raises(Feeds::Discover::Error) { Feeds::Discover.call("  ") }
  end

  test "a link into the private network is refused by the fetcher's guard" do
    Web::Fetch.resolver = Class.new { def getaddresses(_host) = [ "192.168.1.10" ] }.new

    error = assert_raises(Feeds::Discover::Error) { Feeds::Discover.call("https://router.local/feed") }
    assert_match(/private networks/i, error.message)
  end
end
