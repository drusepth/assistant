module Listings
  # Paste anything, get a listing source (D-listing-feeds): `Feeds::Discover`
  # for calendars. Nobody knows their library's iCal URL by heart, so the
  # recipes are the feature:
  #
  #   1. rewrite the addresses whose calendar is a known path (a Meetup
  #      group's iCal export, a public Google Calendar's .ics);
  #   2. fetch the URL itself — a calendar body is an `ics` source as-is;
  #   3. a page's <link rel="alternate" type="text/calendar"> wins as `ics`;
  #   4. otherwise Event structured data on the page makes it a `page`
  #      source;
  #   5. otherwise the conventional paths the common calendar products
  #      expose, capped like the reader's guesses.
  #
  # Every fetch goes through Web::Fetch (SSRF guard, size cap, redirect cap),
  # and nothing is scraped from prose: a page with no feed and no structured
  # data is not a source, and the form says so.
  class Discover
    class Error < StandardError; end

    Found = Data.define(:url, :kind, :title, :items)

    ACCEPT = "text/calendar, application/ld+json;q=0.9, text/html;q=0.8, */*;q=0.5".freeze
    GUESSES = %w[ /calendar.ics /events.ics /events/ical /?ical=1 /feed/ical ].freeze
    MAX_GUESSES = 4
    # A year of a city's calendar is big; the reader's ceiling, not the
    # page's.
    MAX_BYTES = 8.megabytes

    def self.call(url) = new(url).call

    def initialize(url)
      @input = url.to_s.strip
    end

    def call
      raise Error, "Paste a link to a calendar, or to a page that lists events." if @input.blank?

      start = normalize(rewrite(@input))
      page = fetch(start)
      if page
        found = as_calendar(page) || autodiscovered(page) || as_page(page)
        return found if found
      end

      guessed(start) || raise(Error, not_found_message)
    end

    private
      # webcal:// is https:// wearing a calendar app's hat.
      def normalize(url)
        url = url.sub(%r{\Awebcals?://}i, "https://")
        url = "https://#{url}" unless url.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
        uri = URI.parse(url)
        raise Error, "Only http(s) links work here." unless uri.is_a?(URI::HTTP) && uri.host.present?

        uri.to_s
      rescue URI::InvalidURIError
        raise Error, "That doesn't look like a link."
      end

      # The addresses whose calendar is mechanical — documented public paths,
      # each going through exactly the same fetch-and-parse as any other.
      def rewrite(url)
        case url
        when %r{\A(?:https?://)?(?:www\.)?meetup\.com/([A-Za-z0-9_-]+)/?(?:events/?)?\z}i
          "https://www.meetup.com/#{$1}/events/ical/"
        when %r{\A(?:https?://)?calendar\.google\.com/calendar/(?:embed|u/\d+/embed)\?.*?src=([^&]+)}i
          "https://calendar.google.com/calendar/ical/#{$1}/public/basic.ics"
        else
          url
        end
      end

      def as_calendar(page)
        items = Parse::Ics.call(page.text)
        Found.new(url: page.final_url, kind: "ics", title: calendar_title(page.text), items: items) if items
      end

      def as_page(page)
        items = Parse::Schema.call(page.text)
        Found.new(url: page.final_url, kind: "page", title: page.title.to_s.squish.presence, items: items) if items
      end

      def autodiscovered(page)
        candidates(page).each do |candidate|
          found = direct(candidate)
          return found if found
        end
        nil
      end

      # A miss here is expected — most guessed paths 404 — so it never
      # becomes the message; only the address the person actually pasted
      # failing to load is worth reporting as "couldn't read".
      def direct(url)
        page = fetch(url, remember: false)
        page && as_calendar(page)
      end

      def candidates(page)
        Nokogiri::HTML(page.text).css("link[rel~='alternate'][href], a[href$='.ics'], a[href^='webcal:']").filter_map { |link|
          next if link.name == "link" && !link["type"].to_s.match?(%r{text/calendar})

          absolute(link["href"].to_s.sub(%r{\Awebcals?://}i, "https://"), page.final_url)
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

      # X-WR-CALNAME is the calendar's own name, when it has one.
      def calendar_title(body)
        body[/^X-WR-CALNAME[^:]*:(.+)$/i, 1]&.strip&.squish&.truncate(200)
      end

      def fetch(url, remember: true)
        Web::Fetch.raw(url, headers: { "Accept" => ACCEPT }, max_bytes: MAX_BYTES)
      rescue Web::Fetch::Error => e
        @last_error ||= e.message if remember
        nil
      end

      def not_found_message
        return "Couldn't read that address — #{@last_error}." if @last_error

        "No calendar found at that address — look for the site's “Subscribe”, “iCal” or “Add to calendar” link."
      end
  end
end
