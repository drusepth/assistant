require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  FEED = <<~XML.freeze
    <rss><channel><title>The Wood Whisperer</title><link>https://example.com</link>
      <item><title>Scrapers</title><link>https://example.com/1</link></item>
    </channel></rss>
  XML

  setup do
    Web::Fetch.resolver = PUBLIC_DNS
    sign_in_as users(:one)
  end

  teardown { Web::Fetch.resolver = Resolv }

  test "pasting a site follows the feed behind it and names it" do
    stub_request(:get, "https://example.com/blog").to_return(
      body: '<html><head><link rel="alternate" type="application/rss+xml" href="/posts.xml"></head></html>',
      headers: { "Content-Type" => "text/html" }
    )
    stub_request(:get, "https://example.com/posts.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    assert_difference "Feed.count", 1 do
      post feeds_path, params: { feed: { url: "example.com/blog" } }
    end

    feed = users(:one).feeds.sole
    assert_equal "https://example.com/posts.xml", feed.url
    assert_equal "The Wood Whisperer", feed.title
    assert_enqueued_with job: RefreshFeedJob
    assert_redirected_to feeds_path
  end

  test "an address with no feed explains itself and saves nothing" do
    stub_request(:get, %r{https://example\.com}).to_return(body: "<html>nope</html>", headers: { "Content-Type" => "text/html" })

    assert_no_difference "Feed.count" do
      post feeds_path, params: { feed: { url: "https://example.com" } }
    end

    assert_match(/no feed found/i, flash[:alert])
  end

  test "following the same feed twice says so rather than duplicating it" do
    stub_request(:get, "https://example.com/posts.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })
    users(:one).feeds.create!(url: "https://example.com/posts.xml")

    assert_no_difference "Feed.count" do
      post feeds_path, params: { feed: { url: "https://example.com/posts.xml" } }
    end

    assert_match(/already in your reader/i, flash[:alert])
  end

  test "adding from the Hobbies page comes back to the Hobbies page" do
    stub_request(:get, "https://example.com/posts.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    post feeds_path, params: { feed: { url: "https://example.com/posts.xml" }, return_to: section_path("hobbies") }

    assert_redirected_to section_path("hobbies")
  end

  test "filing a feed under a hobby re-scores what is already in the river" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/posts.xml")
    item = feed.feed_items.create!(guid: "1", title: "A woodworking bench", published_at: 1.hour.ago)

    patch feed_path(feed), params: { feed: { section_ids: [ lens.id ] } }

    assert_operator item.reload.relevance, :>, 0.5
  end

  test "another member's feed is untouchable" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")

    patch feed_path(theirs), params: { feed: { label: "Mine now" } }
    assert_response :not_found

    delete feed_path(theirs)
    assert_response :not_found
    assert Feed.exists?(theirs.id)
  end

  test "unfollowing takes the items with it" do
    feed = users(:one).feeds.create!(url: "https://example.com/posts.xml")
    feed.feed_items.create!(guid: "1", title: "One")

    assert_difference [ "Feed.count", "FeedItem.count" ], -1 do
      delete feed_path(feed)
    end
  end

  test "check-now reports the failure on the feed rather than blowing up" do
    feed = users(:one).feeds.create!(url: "https://example.com/posts.xml")
    stub_request(:get, feed.url).to_return(status: 503)

    post refresh_feed_path(feed)

    assert_redirected_to feeds_path
    assert_match(/503/, feed.reload.last_error)
  end

  test "check-all enqueues one fetch per active feed" do
    users(:one).feeds.create!(url: "https://example.com/a.xml")
    users(:one).feeds.create!(url: "https://example.com/b.xml", active: false)

    assert_enqueued_jobs 1, only: RefreshFeedJob do
      post refresh_all_feeds_path
    end
  end

  test "the index lists your feeds and nobody else's" do
    users(:one).feeds.create!(url: "https://example.com/mine.xml", label: "Mine")
    users(:two).feeds.create!(url: "https://example.com/theirs.xml", label: "Theirs")

    get feeds_path

    assert_response :success
    assert_select "body", text: /Mine/
    assert_select "body", { text: /Theirs/, count: 0 }
  end
end
