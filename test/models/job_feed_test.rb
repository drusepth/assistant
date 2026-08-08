require "test_helper"

class JobFeedTest < ActiveSupport::TestCase
  test "kind is sniffed from the pasted URL" do
    assert_equal "greenhouse", feed("https://boards.greenhouse.io/acme").kind
    assert_equal "lever", feed("https://jobs.lever.co/acme").kind
    assert_equal "usajobs", feed("https://data.usajobs.gov/api/search?Keyword=warehouse").kind
    assert_equal "rss", feed("https://weworkremotely.com/categories/remote-devops-jobs.rss").kind
  end

  test "board pages normalize to their JSON APIs for fetching" do
    assert_equal "https://boards-api.greenhouse.io/v1/boards/acme/jobs",
      feed("https://boards.greenhouse.io/acme").fetch_url
    assert_equal "https://api.lever.co/v0/postings/acme?mode=json",
      feed("https://jobs.lever.co/acme").fetch_url
    rss = feed("https://example.com/jobs.rss")
    assert_equal rss.url, rss.fetch_url
  end

  test "usajobs sends its documented auth headers" do
    usajobs = feed("https://data.usajobs.gov/api/search", api_key: "k123")

    assert_equal "k123", usajobs.fetch_headers["Authorization-Key"]
    assert_equal users(:one).email_address, usajobs.fetch_headers["User-Agent"]
    assert_empty feed("https://example.com/jobs.rss").fetch_headers
  end

  test "a non-link is rejected" do
    assert_not JobFeed.new(user: users(:one), url: "acme jobs").valid?
  end

  private
    def feed(url, api_key: nil)
      users(:one).job_feeds.create!(url: url, api_key: api_key)
    end
end
