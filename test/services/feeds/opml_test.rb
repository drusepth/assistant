require "test_helper"

class Feeds::OpmlTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @lens = Hobbies::Lens.find_or_create!("Woodworking")
  end

  test "export nests feeds under their hobby, and leaves untagged ones at the top" do
    @user.feeds.create!(url: "https://example.com/wood.xml", title: "The Wood Whisperer",
      site_url: "https://example.com", sections: [ @lens ])
    @user.feeds.create!(url: "https://example.com/misc.xml", title: "Hacker News")

    document = Nokogiri::XML(Feeds::Opml.export(@user))

    top = document.css("body > outline")
    assert_equal [ "Hacker News", "Woodworking" ], top.map { |node| node["text"] }
    folder = top.last
    assert_equal "The Wood Whisperer", folder.css("outline").sole["title"]
    assert_equal "https://example.com/wood.xml", folder.css("outline").sole["xmlUrl"]
    assert_equal "https://example.com", folder.css("outline").sole["htmlUrl"]
  end

  test "what we export, we can import" do
    @user.feeds.create!(url: "https://example.com/wood.xml", title: "The Wood Whisperer", sections: [ @lens ])
    xml = Feeds::Opml.export(@user)
    other = users(:two)

    result = Feeds::Opml.import(other, xml)

    assert result.ok?
    assert_equal 1, result.added
    feed = other.feeds.sole
    assert_equal "https://example.com/wood.xml", feed.url
    assert_equal [ @lens ], feed.sections.to_a, "a folder that matches a hobby files the feed under it"
  end

  test "a folder with no matching hobby leaves the feed untagged unless asked" do
    xml = <<~XML
      <opml version="2.0"><body>
        <outline text="Cycling">
          <outline type="rss" text="Bike Blog" xmlUrl="https://example.com/bikes.xml"/>
        </outline>
      </body></opml>
    XML

    result = Feeds::Opml.import(@user, xml)

    assert_equal 1, result.added
    assert_empty @user.feeds.sole.sections
    assert_empty result.lenses
    assert_nil Hobbies::Lens.named("Cycling"), "an import doesn't quietly grow the taxonomy"
  end

  test "…and creates the hobby when the user does ask" do
    xml = <<~XML
      <opml version="2.0"><body>
        <outline text="Cycling">
          <outline type="rss" text="Bike Blog" xmlUrl="https://example.com/bikes.xml"/>
        </outline>
      </body></opml>
    XML

    result = Feeds::Opml.import(@user, xml, create_lenses: true)

    assert_equal [ "Cycling" ], result.lenses
    assert_equal "Cycling", @user.feeds.sole.sections.sole.name
    assert Hobbies::Lens.named("Cycling")
  end

  test "importing enqueues a check for each new feed, and fetches nothing itself" do
    xml = '<opml><body><outline type="rss" xmlUrl="https://example.com/a.xml"/></body></opml>'

    assert_enqueued_jobs 1, only: RefreshFeedJob do
      Feeds::Opml.import(@user, xml)
    end
  end

  test "feeds already followed are counted as skipped, not duplicated" do
    @user.feeds.create!(url: "https://example.com/a.xml")
    xml = <<~XML
      <opml><body>
        <outline type="rss" xmlUrl="https://example.com/a.xml"/>
        <outline type="rss" xmlUrl="https://example.com/b.xml"/>
      </body></opml>
    XML

    result = Feeds::Opml.import(@user, xml)

    assert_equal 1, result.added
    assert_equal 1, result.skipped
    assert_equal 2, @user.feeds.count
  end

  test "junk in the file is skipped rather than fatal" do
    xml = <<~XML
      <opml><body>
        <outline text="A folder with no feeds"/>
        <outline type="rss" xmlUrl="javascript:alert(1)"/>
        <outline type="rss" xmlUrl="not a url"/>
        <outline type="rss" xmlUrl="https://example.com/good.xml"/>
        <outline type="rss" xmlUrl="https://example.com/good.xml"/>
      </body></opml>
    XML

    result = Feeds::Opml.import(@user, xml)

    assert_equal 1, result.added, "one good feed, once"
    assert_equal [ "https://example.com/good.xml" ], @user.feeds.pluck(:url)
  end

  test "a file that isn't OPML says so instead of importing nothing quietly" do
    result = Feeds::Opml.import(@user, "<html><body>hello</body></html>")

    assert_not result.ok?
    assert_match(/no feeds/i, result.error)
  end

  test "an absurd file is refused before it is parsed" do
    result = Feeds::Opml.import(@user, "x" * (Feeds::Opml::MAX_BYTES + 1))

    assert_not result.ok?
    assert_match(/too big/i, result.error)
  end
end
