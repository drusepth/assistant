require "test_helper"

class Feeds::ParseTest < ActiveSupport::TestCase
  test "RSS 2.0 with the fields publishers actually ship" do
    body = <<~XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
           xmlns:dc="http://purl.org/dc/elements/1.1/">
        <channel>
          <title>The Wood Whisperer</title>
          <link>https://example.com</link>
          <description>Woodworking, weekly</description>
          <item>
            <title>Sharpening a card scraper</title>
            <link>https://example.com/scraper</link>
            <guid isPermaLink="false">tag:example.com,2026:1</guid>
            <dc:creator>Marc</dc:creator>
            <description>&lt;p&gt;A burnisher and &lt;b&gt;five minutes&lt;/b&gt;.&lt;/p&gt;</description>
            <pubDate>Tue, 18 Aug 2026 09:00:00 +0000</pubDate>
            <enclosure url="https://example.com/scraper.jpg" type="image/jpeg"/>
          </item>
        </channel>
      </rss>
    XML

    result = Feeds::Parse.call(body)

    assert_equal "rss", result.kind
    assert_equal "The Wood Whisperer", result.title
    assert_equal "https://example.com", result.site_url

    entry = result.entries.sole
    assert_equal "Sharpening a card scraper", entry.title
    assert_equal "https://example.com/scraper", entry.url
    assert_equal "tag:example.com,2026:1", entry.guid
    assert_equal "Marc", entry.author
    assert_equal "A burnisher and five minutes.", entry.summary, "publisher HTML is stripped at the door"
    assert_equal "https://example.com/scraper.jpg", entry.image_url
    assert_equal Time.utc(2026, 8, 18, 9), entry.published_at
  end

  test "Atom, preferring the alternate link over self" do
    body = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Fretboard Journal</title>
        <link rel="self" href="https://example.com/feed.atom"/>
        <link rel="alternate" href="https://example.com"/>
        <entry>
          <title>A luthier's bench</title>
          <id>urn:uuid:1</id>
          <link rel="self" href="https://example.com/bench.atom"/>
          <link rel="alternate" href="https://example.com/bench"/>
          <author><name>Kim</name></author>
          <summary>Bench build.</summary>
          <updated>2026-08-01T12:00:00Z</updated>
        </entry>
      </feed>
    XML

    result = Feeds::Parse.call(body)

    assert_equal "atom", result.kind
    assert_equal "https://example.com", result.site_url
    entry = result.entries.sole
    assert_equal "https://example.com/bench", entry.url, "a reader wants the article, not the feed's own address"
    assert_equal "urn:uuid:1", entry.guid
    assert_equal "Kim", entry.author
  end

  test "JSON Feed" do
    body = {
      version: "https://jsonfeed.org/version/1.1", title: "Knitty",
      home_page_url: "https://example.com",
      items: [ { id: "17", url: "https://example.com/sock", title: "A better heel",
                 content_text: "Turn it once.", date_published: "2026-08-20T08:00:00Z" } ]
    }.to_json

    result = Feeds::Parse.call(body)

    assert_equal "json", result.kind
    entry = result.entries.sole
    assert_equal "17", entry.guid
    assert_equal "A better heel", entry.title
    assert_equal "Turn it once.", entry.summary
  end

  test "RSS 1.0 / RDF, which is still out there" do
    body = <<~XML
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
        <channel><title>Old School</title></channel>
        <item rdf:about="https://example.com/one"><title>One</title></item>
      </rdf:RDF>
    XML

    result = Feeds::Parse.call(body)

    assert_equal "Old School", result.title
    assert_equal "https://example.com/one", result.entries.sole.url, "RDF items carry their link in rdf:about"
  end

  test "an entry with neither title nor link is dropped, and never fatal" do
    body = <<~XML
      <rss><channel><title>Half broken</title>
        <item><description>orphan</description></item>
        <item><title>Good one</title><link>https://example.com/good</link></item>
      </channel></rss>
    XML

    assert_equal [ "Good one" ], Feeds::Parse.call(body).entries.map(&:title)
  end

  test "an item with no date at all still parses" do
    body = "<rss><channel><title>T</title><item><title>Undated</title><link>https://e.com/1</link></item></channel></rss>"

    assert_nil Feeds::Parse.call(body).entries.sole.published_at
  end

  test "HTML, plain text and nonsense are not feeds" do
    assert_nil Feeds::Parse.call("<html><body><h1>A blog</h1></body></html>")
    assert_nil Feeds::Parse.call("not a feed at all")
    assert_nil Feeds::Parse.call("")
    assert_nil Feeds::Parse.call(nil)
    assert_nil Feeds::Parse.call('{"nope": true}')
  end

  test "a feed that names an external entity does not fetch or expand it" do
    body = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE rss [<!ENTITY secret SYSTEM "file:///etc/passwd">]>
      <rss><channel><title>Hostile</title>
        <item><title>&secret;</title><link>https://example.com/x</link></item>
      </channel></rss>
    XML

    result = Feeds::Parse.call(body)

    assert_not_includes result.entries.map(&:title).join, "root:", "external entities stay unexpanded"
  end
end
