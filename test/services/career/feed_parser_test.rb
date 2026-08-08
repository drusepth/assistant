require "test_helper"

class Career::FeedParserTest < ActiveSupport::TestCase
  test "greenhouse board JSON" do
    body = { jobs: [
      { title: "Warehouse Lead", absolute_url: "https://boards.greenhouse.io/acme/jobs/1", location: { name: "Columbus, OH" } },
      { title: "", absolute_url: "https://boards.greenhouse.io/acme/jobs/2" }
    ] }.to_json

    postings = Career::FeedParser.parse("greenhouse", body, fallback_company: "Acme")

    posting = postings.sole
    assert_equal "Warehouse Lead", posting.title
    assert_equal "Acme", posting.company
    assert_equal "Columbus, OH", posting.location
  end

  test "lever postings JSON" do
    body = [ { text: "Night Supervisor", hostedUrl: "https://jobs.lever.co/acme/x", categories: { location: "Remote" } } ].to_json

    posting = Career::FeedParser.parse("lever", body, fallback_company: "Acme").sole
    assert_equal "Night Supervisor", posting.title
    assert_equal "Remote", posting.location
  end

  test "usajobs search JSON" do
    body = { SearchResult: { SearchResultItems: [ { MatchedObjectDescriptor: {
      PositionTitle: "Logistics Management Specialist", PositionURI: "https://www.usajobs.gov/job/1",
      OrganizationName: "Defense Logistics Agency", PositionLocationDisplay: "Columbus, Ohio"
    } } ] } }.to_json

    posting = Career::FeedParser.parse("usajobs", body).sole
    assert_equal "Logistics Management Specialist", posting.title
    assert_equal "Defense Logistics Agency", posting.company
  end

  test "rss and atom items" do
    rss = <<~XML
      <rss><channel><item><title>Forklift Operator — Acme</title><link>https://example.com/jobs/9</link></item></channel></rss>
    XML
    atom = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Dispatcher</title><link href="https://example.com/jobs/10"/></entry></feed>
    XML

    assert_equal "Forklift Operator — Acme", Career::FeedParser.parse("rss", rss).sole.title
    assert_equal "https://example.com/jobs/10", Career::FeedParser.parse("rss", atom).sole.url
  end

  test "garbage bodies parse to nothing, never an exception" do
    assert_empty Career::FeedParser.parse("greenhouse", "not json")
    assert_empty Career::FeedParser.parse("rss", "<rss><unclosed")
  end
end
