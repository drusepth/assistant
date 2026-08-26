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

  # D-hobby-feeds: adding a feed fetches in the request (the user needs to
  # know the subscription is real) but files it in a job (a slow provider
  # must not hold the form).
  test "a new feed asks the model which hobby it is, in a job" do
    Hobbies::Lens.find_or_create!("Woodworking")
    stub_request(:get, "https://example.com/posts.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    assert_enqueued_with(job: ClassifyFeedJob) do
      post feeds_path, params: { feed: { url: "https://example.com/posts.xml" } }
    end
  end

  test "a feed the user filed by hand on the way in is not re-filed" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    stub_request(:get, "https://example.com/posts.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    assert_no_enqueued_jobs(only: ClassifyFeedJob) do
      post feeds_path, params: { feed: { url: "https://example.com/posts.xml", section_ids: [ lens.id ] } }
    end
    assert_equal [ lens ], users(:one).feeds.sole.sections.to_a
  end

  test "with no model a new feed still gets a home, without a round trip" do
    users(:one).household.model_profile.update!(api_key: "")
    stub_request(:get, "https://example.com/posts.xml").to_return(body: FEED, headers: { "Content-Type" => "application/rss+xml" })

    assert_no_enqueued_jobs(only: ClassifyFeedJob) do
      post feeds_path, params: { feed: { url: "https://example.com/posts.xml" } }
    end
    assert_equal [ Hobbies::OtherInterests.find ], users(:one).feeds.sole.sections.to_a
  end

  test "re-file asks again, and says so plainly when there is nobody to ask" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/posts.xml", sections: [ lens ])

    assert_enqueued_with(job: ClassifyFeedJob) { post refile_feed_path(feed) }
    assert_match(/Re-filing/, flash[:notice])

    users(:one).household.model_profile.update!(api_key: "")
    assert_no_enqueued_jobs(only: ClassifyFeedJob) { post refile_feed_path(feed) }
    assert_match(/filed by hand/, flash[:notice])
  end

  test "re-file is your own feeds only" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")

    post refile_feed_path(theirs)

    assert_response :not_found
  end

  # Filing a stray where you noticed it was stray (D-hobby-feeds).
  test "the feed list files a stray feed inline, and says why it is stray" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/wood.xml", label: "Wood")
    feed.sections = [ Hobbies::OtherInterests.find_or_create! ]

    get feeds_path
    assert_match(/not filed yet/, response.body)
    assert_select "select[name='feed[section_ids][]']"

    patch feed_path(feed), params: { feed: { section_ids: [ lens.id ] }, return_to: feeds_path(unfiled: 1) }

    assert_equal [ lens ], feed.reload.sections.to_a
    assert_redirected_to feeds_path(unfiled: 1)
  end

  test "a filed feed gets neither the picker nor Re-file" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    users(:one).feeds.create!(url: "https://example.com/wood.xml", sections: [ lens ])

    get feeds_path

    assert_select "select[name='feed[section_ids][]']", false
    assert_no_match(/Re-file/, response.body)
  end

  test "the list narrows to the strays, and says how many there are" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    filed = users(:one).feeds.create!(url: "https://example.com/wood.xml", label: "Filed", sections: [ lens ])
    stray = users(:one).feeds.create!(url: "https://example.com/news.xml", label: "Stray")
    stray.sections = [ Hobbies::OtherInterests.find_or_create! ]

    get feeds_path
    assert_match "1 with no hobby", response.body

    get feeds_path(unfiled: 1)
    assert_match stray.display_title, response.body
    assert_no_match filed.display_title, response.body
  end

  test "a feed the model considered and passed on says so" do
    feed = users(:one).feeds.create!(url: "https://example.com/news.xml", classified_at: Time.current)
    feed.sections = [ Hobbies::OtherInterests.find_or_create! ]

    get feeds_path

    assert_match(/no hobby matched/, response.body)
  end

  # D-hobby-feeds §7.1: offered, never subscribed.
  test "the starter shelf appears only while there is nothing to read" do
    get feeds_path
    assert_match(/Not sure where to start/, response.body)
    assert_no_difference("Feed.count") { get reader_path }

    users(:one).feeds.create!(url: "https://example.com/mine.xml")

    get feeds_path
    assert_no_match(/Not sure where to start/, response.body)
    get reader_path
    assert_no_match(/Not sure where to start/, response.body)
  end

  test "ticking starters follows those and returns to where the shelf was" do
    picks = Feeds::Starters.entries.first(2).map(&:url)

    assert_difference "Feed.count", 2 do
      post starters_feeds_path, params: { urls: picks, create_lenses: "1", return_to: section_path("hobbies") }
    end

    assert_redirected_to section_path("hobbies")
    assert_equal picks.sort, users(:one).feeds.pluck(:url).sort
  end

  test "submitting the shelf with nothing ticked says so and follows nothing" do
    assert_no_difference "Feed.count" do
      post starters_feeds_path, params: { urls: [] }
    end

    assert_match(/Pick at least one/, flash[:alert])
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

  test "filing a feed under a hobby is what the river's hobby filter reads" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/posts.xml")

    patch feed_path(feed), params: { feed: { section_ids: [ lens.id ] } }

    assert_equal [ lens ], feed.reload.sections.to_a
    assert_equal [ feed ], Feed.in_section(lens).to_a
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

  test "check-now hands the fetch to a job instead of holding the request" do
    feed = users(:one).feeds.create!(url: "https://example.com/posts.xml")

    assert_enqueued_with job: RefreshFeedJob, args: [ feed ] do
      post refresh_feed_path(feed)
    end

    assert_redirected_to feeds_path
    assert_match(/checking/i, flash[:notice])
    assert_not_requested :get, feed.url
  end

  test "a failing feed's own row still says what went wrong" do
    feed = users(:one).feeds.create!(url: "https://example.com/posts.xml")
    stub_request(:get, feed.url).to_return(status: 503)

    perform_enqueued_jobs { post refresh_feed_path(feed) }

    assert_match(/503/, feed.reload.last_error)
    get feeds_path
    assert_match(/503/, response.body)
  end

  test "the reading list exports as OPML" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    users(:one).feeds.create!(url: "https://example.com/wood.xml", title: "Wood", sections: [ lens ])

    get export_feeds_path

    assert_response :success
    assert_equal "text/x-opml", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match "https://example.com/wood.xml", response.body
  end

  test "an OPML file becomes subscriptions, checked in the background" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new('<opml><body><outline type="rss" xmlUrl="https://example.com/a.xml"/></body></opml>'),
      "text/x-opml", original_filename: "subscriptions.opml"
    )

    assert_difference "Feed.count", 1 do
      assert_enqueued_jobs 1, only: RefreshFeedJob do
        post import_feeds_path, params: { file: file }
      end
    end

    assert_redirected_to feeds_path
    assert_match(/1 feed added/i, flash[:notice])
    assert_not_requested :get, "https://example.com/a.xml"
  end

  test "importing nothing explains itself" do
    post import_feeds_path

    assert_match(/choose an opml file/i, flash[:alert])
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
