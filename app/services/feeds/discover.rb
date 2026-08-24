module Feeds
  # Paste anything, get a feed (D-feed-reader). Google Reader's one piece of
  # real magic was that you handed it the address of a site you liked and it
  # worked out the rest; asking a person to find the orange XML icon is
  # exactly the friction that made feeds feel like a hobbyist's format.
  #
  # Four passes, cheapest first, each one a real fetch through Web::Fetch
  # (so the SSRF guard, the size cap and the redirect cap all apply):
  #
  #   1. rewrite the addresses whose feed is a known suffix (a subreddit, a
  #      YouTube channel, a GitHub repo's releases),
  #   2. try the URL itself — most pastes are already a feed,
  #   3. read the page's <link rel="alternate"> autodiscovery tags,
  #   4. guess the handful of conventional paths (/feed, /rss.xml, …).
  #
  # Only the first success is used, and nothing is ever guessed *after* a
  # page has told us where its feed is.
  class Discover
    class Error < StandardError; end

    Found = Data.define(:url, :parsed)

    # Feed servers are picky about negotiation in both directions: ask for
    # feeds first, but accept HTML, since pass 3 needs the page.
    ACCEPT = "application/rss+xml, application/atom+xml, application/feed+json, " \
             "application/xml;q=0.9, text/xml;q=0.9, text/html;q=0.8, */*;q=0.5".freeze

    GUESSES = %w[ /feed /feed.xml /rss /rss.xml /atom.xml /index.xml /feed.json ].freeze
    MAX_GUESSES = 4

    def self.call(url) = new(url).call

    def initialize(url)
      @input = url.to_s.strip
    end

    def call
      raise Error, "Paste a link to a site or a feed." if @input.blank?

      start = normalize(rewrite(@input))
      # One fetch covers passes 2 and 3: a feed body parses, and an HTML
      # body still carries its autodiscovery tags because this fetch keeps
      # the markup.
      page = fetch(start)
      if page
        parsed = Parse.call(page.text)
        return Found.new(url: page.final_url, parsed: parsed) if parsed

        found = autodiscovered(page)
        return found if found
      end

      guessed(start) || raise(Error, not_found_message)
    end

    private
      # A bare "example.com/blog" is what people paste; assume https rather
      # than refusing, and never silently accept a non-http scheme (a
      # `javascript:` or `file:` paste has no business reaching a fetcher).
      def normalize(url)
        url = "https://#{url}" unless url.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
        uri = URI.parse(url)
        raise Error, "Only http(s) links work here." unless uri.is_a?(URI::HTTP) && uri.host.present?

        uri.to_s
      rescue URI::InvalidURIError
        raise Error, "That doesn't look like a link."
      end

      # The addresses whose feed is mechanical. These are conveniences, not
      # integrations: each one is a documented public feed path, and the
      # result goes through exactly the same fetch-and-parse as any other.
      def rewrite(url)
        case url
        when %r{\A(?:https?://)?(?:www\.|old\.)?reddit\.com(/r/[A-Za-z0-9_]+)/?\z}i
          "https://www.reddit.com#{$1}/.rss"
        when %r{\A(?:https?://)?(?:www\.)?youtube\.com/channel/([A-Za-z0-9_-]+)/?\z}i
          "https://www.youtube.com/feeds/videos.xml?channel_id=#{$1}"
        when %r{\A(?:https?://)?(?:www\.)?github\.com/([\w.-]+/[\w.-]+)/?\z}i
          "https://github.com/#{$1}/releases.atom"
        else
          url
        end
      end

      def direct(url)
        page = fetch(url)
        parsed = page && Parse.call(page.text)
        Found.new(url: page.final_url, parsed: parsed) if parsed
      end

      def autodiscovered(page)
        candidates(page).each do |candidate|
          found = direct(candidate)
          return found if found
        end
        nil
      end

      # <link rel="alternate" type="application/rss+xml" href="…"> — the
      # tag that made "paste the site" possible in the first place.
      def candidates(page)
        Nokogiri::HTML(page.text).css("link[rel~='alternate'][href]").filter_map { |link|
          next unless link["type"].to_s.match?(%r{(rss|atom)\+xml|feed\+json})

          absolute(link["href"], page.final_url)
        }.uniq.first(3)
      end

      def guessed(url)
        base = URI.parse(url)
        root = "#{base.scheme}://#{base.host}#{base.port == base.default_port ? "" : ":#{base.port}"}"
        GUESSES.first(MAX_GUESSES).each do |path|
          candidate = "#{root}#{path}"
          next if candidate == url

          found = direct(candidate)
          return found if found
        end
        nil
      rescue URI::InvalidURIError
        nil
      end

      def absolute(href, base)
        URI.join(base, href).to_s
      rescue URI::InvalidURIError, URI::BadURIError
        nil
      end

      # A miss on any one pass is data, not an error: pass 4 tries four
      # addresses precisely because most of them will 404. The first
      # failure is kept, though — "couldn't reach the site" and "that page
      # has no feed" are different problems for the person pasting.
      def fetch(url)
        Web::Fetch.raw(url, headers: { "Accept" => ACCEPT })
      rescue Web::Fetch::Error => e
        @last_error ||= e.message
        nil
      end

      def not_found_message
        return "Couldn't read that address — #{@last_error}." if @last_error

        "No feed found at that address — try the site's “RSS” or “Subscribe” link."
      end
  end
end
