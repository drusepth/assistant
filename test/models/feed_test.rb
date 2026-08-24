require "test_helper"

class FeedTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a feed needs an http(s) address" do
    assert @user.feeds.new(url: "https://example.com/feed.xml").valid?
    assert_not @user.feeds.new(url: "example.com/feed.xml").valid?
    assert_not @user.feeds.new(url: "javascript:alert(1)").valid?
    # Ruby regexes are multiline, so an unanchored tail would let this pass.
    assert_not @user.feeds.new(url: "https://ok.example/feed\njavascript:alert(1)").valid?
  end

  test "the same feed is not followed twice by one user, but two people may each follow it" do
    @user.feeds.create!(url: "https://example.com/feed.xml")

    assert_not @user.feeds.new(url: "https://example.com/feed.xml").valid?
    assert users(:two).feeds.new(url: "https://example.com/feed.xml").valid?
  end

  test "the display name prefers the user's label, then the feed's own title" do
    feed = @user.feeds.create!(url: "https://example.com/feed.xml", title: "The Wood Whisperer")
    assert_equal "The Wood Whisperer", feed.display_title

    feed.update!(label: "Woodworking podcast")
    assert_equal "Woodworking podcast", feed.display_title

    bare = @user.feeds.create!(url: "https://www.example.org/atom.xml")
    assert_equal "example.org", bare.display_title
  end

  test "a failing feed is checked less often, and a healthy one hourly" do
    feed = @user.feeds.create!(url: "https://example.com/feed.xml")
    assert feed.due_for_refresh?, "never fetched is always due"

    feed.record_success!
    assert_not feed.due_for_refresh?
    travel 61.minutes do
      assert feed.due_for_refresh?
    end

    3.times { feed.record_failure!("the site answered HTTP 500") }
    travel 2.hours do
      assert_not feed.due_for_refresh?, "a feed that keeps failing backs off instead of being hammered"
    end
    travel 2.days do
      assert feed.due_for_refresh?, "backoff is capped — a site that comes back is picked up again"
    end
  end

  test "the SQL prefilter never misses a feed the exact check would pick up" do
    fresh = @user.feeds.create!(url: "https://example.com/a.xml")
    fresh.record_success!
    stale = @user.feeds.create!(url: "https://example.com/b.xml")
    stale.update!(last_fetched_at: 3.hours.ago)
    paused = @user.feeds.create!(url: "https://example.com/c.xml", active: false)

    due = Feed.due_for_refresh.to_a

    assert_includes due, stale
    assert_not_includes due, fresh
    assert_not_includes due, paused
  end

  test "a feed nobody reads any more is polled half as eagerly" do
    feed = @user.feeds.create!(url: "https://example.com/feed.xml")
    feed.feed_items.create!(guid: "1", title: "Old news", published_at: 90.days.ago)
    feed.record_success!(last_item_at: 90.days.ago)

    assert feed.dormant?
    assert_operator feed.refresh_interval, :>, Feed::REFRESH_EVERY
  end

  test "dormancy is read off the row, not counted from the items" do
    feed = @user.feeds.create!(url: "https://example.com/feed.xml")
    feed.feed_items.create!(guid: "1", title: "Old news", published_at: 90.days.ago)
    feed.record_success!(last_item_at: 90.days.ago)
    feed.reload

    # One query per feed inside the sweep was the whole point of the
    # `last_read_at` column — this pins that it stays zero.
    assert_no_queries { feed.dormant? }
    assert_no_queries { feed.due_for_refresh? }
  end

  test "reading something here wakes the feed back up" do
    feed = @user.feeds.create!(url: "https://example.com/feed.xml")
    item = feed.feed_items.create!(guid: "1", title: "Old news", published_at: 90.days.ago)
    feed.record_success!(last_item_at: 90.days.ago)
    assert feed.dormant?

    item.mark_read!

    assert_not feed.reload.dormant?
    assert_equal Feed::REFRESH_EVERY, feed.refresh_interval
  end

  test "the validators only go back out when the publisher gave us some" do
    feed = @user.feeds.create!(url: "https://example.com/feed.xml")
    assert_empty feed.conditional_headers

    feed.update!(etag: "\"abc\"", last_modified: "Tue, 18 Aug 2026 09:00:00 GMT")

    assert_equal({ "If-None-Match" => "\"abc\"",
                   "If-Modified-Since" => "Tue, 18 Aug 2026 09:00:00 GMT" }, feed.conditional_headers)
  end

  test "unfollowing a feed takes its items with it" do
    feed = @user.feeds.create!(url: "https://example.com/feed.xml")
    feed.feed_items.create!(guid: "1", title: "One")

    assert_difference("FeedItem.count", -1) { feed.destroy! }
  end

  test "a feed is taggable by hobby lens like any other primitive" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = @user.feeds.create!(url: "https://example.com/feed.xml", sections: [ lens ])

    assert_equal [ feed ], Feed.in_section(lens).to_a
  end
end
