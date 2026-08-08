require "test_helper"

# The D32 app-side web floor: deterministic fetch, structural guardrails —
# private-network refusal, redirect and size caps, text-only extraction.
class WebFetchTest < ActiveSupport::TestCase
  PUBLIC_DNS = Class.new do
    def getaddresses(_host) = [ "93.184.216.34" ]
  end.new

  setup { Web::Fetch.resolver = PUBLIC_DNS }
  teardown { Web::Fetch.resolver = Resolv }

  test "extracts readable text and the title from an HTML page" do
    stub_request(:get, "https://jobs.example.com/listing/42").to_return(
      status: 200, headers: { "Content-Type" => "text/html" },
      body: "<html><head><title>Shift Lead — Acme</title><script>tracker()</script></head>" \
            "<body><h1>Shift Lead</h1><p>Leads a team of 12.</p></body></html>"
    )

    page = Web::Fetch.text("https://jobs.example.com/listing/42")

    assert_equal "Shift Lead — Acme", page.title
    assert_includes page.text, "Leads a team of 12."
    assert_not_includes page.text, "tracker", "script bodies never reach the model"
  end

  test "follows a redirect and reports the final URL" do
    stub_request(:get, "https://jobs.example.com/short").to_return(
      status: 302, headers: { "Location" => "https://jobs.example.com/long" }
    )
    stub_request(:get, "https://jobs.example.com/long").to_return(
      status: 200, headers: { "Content-Type" => "text/plain" }, body: "the posting"
    )

    page = Web::Fetch.text("https://jobs.example.com/short")

    assert_equal "https://jobs.example.com/long", page.final_url
    assert_equal "the posting", page.text
  end

  test "refuses links that resolve into private networks" do
    Web::Fetch.resolver = Class.new do
      def getaddresses(_host) = [ "10.0.0.5" ]
    end.new

    error = assert_raises(Web::Fetch::Error) { Web::Fetch.text("https://internal.example.com/") }
    assert_match(/private networks/, error.message)
  end

  test "refuses literal loopback addresses" do
    Web::Fetch.resolver = Resolv # IP literals resolve to themselves, no DNS needed

    error = assert_raises(Web::Fetch::Error) { Web::Fetch.text("http://127.0.0.1/admin") }
    assert_match(/private networks/, error.message)
  end

  test "refuses non-http schemes, non-links, and unreadable content types" do
    assert_raises(Web::Fetch::Error) { Web::Fetch.text("ftp://example.com/file") }
    assert_raises(Web::Fetch::Error) { Web::Fetch.text("not a url") }

    stub_request(:get, "https://jobs.example.com/logo").to_return(
      status: 200, headers: { "Content-Type" => "image/png" }, body: "bytes"
    )
    error = assert_raises(Web::Fetch::Error) { Web::Fetch.text("https://jobs.example.com/logo") }
    assert_match(%r{image/png}, error.message)
  end

  test "an error status is reported plainly" do
    stub_request(:get, "https://jobs.example.com/gone").to_return(status: 404, body: "")

    error = assert_raises(Web::Fetch::Error) { Web::Fetch.text("https://jobs.example.com/gone") }
    assert_match(/HTTP 404/, error.message)
  end
end
