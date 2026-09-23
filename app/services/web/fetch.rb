require "net/http"
require "resolv"
require "ipaddr"

module Web
  # The app-side web floor (D-career-web): deterministic code fetches one
  # user-supplied URL and hands the model text — the model never drives the
  # connection, so this works identically on a frontier API and a local
  # 7B model, and what was fetched is auditable. Guardrails are structural:
  # size cap, redirect cap, and a private-address block so a URL can never
  # be aimed at the instance's own network (self-hosted boxes have
  # neighbors; SSRF is the classic way in).
  class Fetch
    class Error < StandardError; end

    MAX_BYTES = 2.megabytes
    MAX_REDIRECTS = 3
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 20
    TOO_LARGE = "the page is too large to read".freeze

    # The conventional well-behaved-bot form, and the change is not cosmetic:
    # this was a bare token (`assistant-self-hosted (+url)`), and the first
    # full run of the starter-shelf checker answered 403 on ~30 of 326
    # ordinary publisher feeds — Mr. Money Mustache, Stronger by Science,
    # Shut Up & Sit Down, Harvard Health. Naive WAF rules (Wordfence, Sucuri,
    # Cloudflare's bot rules) refuse anything that doesn't parse as a
    # `Mozilla/5.0 (compatible; …)` agent string, which is the shape
    # Googlebot and every feed reader since Bloglines has used. It is no less
    # honest — the app still names itself and links to its source — and it is
    # what stands between a self-hoster and a reader that silently can't read
    # a tenth of the open web.
    USER_AGENT = "Mozilla/5.0 (compatible; assistant/1.0; +https://github.com/drusepth/assistant)".freeze

    BLOCKED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.168.0.0/16 ::1/128 fc00::/7 fe80::/10
    ].map { |range| IPAddr.new(range) }.freeze

    # `headers` and `not_modified` exist for the reader's conditional GET
    # (D-feed-reader): a caller that sent If-None-Match needs the validators
    # back, and needs "nothing changed" to be an *answer* rather than an
    # error. Everything else can ignore both.
    Page = Data.define(:title, :text, :final_url, :headers, :not_modified) do
      def not_modified? = not_modified
    end

    # Injectable so tests run without DNS; anything answering getaddresses.
    cattr_accessor :resolver, default: Resolv

    def self.text(url, **options) = new(url, **options).call

    # The same fetch with the markup left on. Only the reader's feed
    # discovery wants this (D-feed-reader): finding a site's <link
    # rel="alternate"> means reading the tags the text extraction exists to
    # throw away. Everything that hands a page to a *model* still goes
    # through .text — raw markup is never prompt material.
    def self.raw(url, **options) = new(url, raw: true, **options).call

    # Timeouts are per call because they are a product decision, not a
    # network one: the defaults suit a background job, and a fetch somebody
    # is *waiting on* in a form submit wants to give up much sooner.
    # `max_bytes` is per call for the same reason the timeouts are: 2MB is
    # the right ceiling for "a page somebody pasted", and the wrong one for a
    # feed. A full-content Atom file is routinely bigger than that — the
    # shelf checker found three (danluu.com, Podnews, Hagerty) that the
    # reader was refusing to read at all, which is a subscription that
    # silently never updates rather than an error anybody sees.
    def initialize(url, headers: {}, raw: false, max_bytes: MAX_BYTES,
                   open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      @url = url.to_s.strip
      @headers = headers
      @raw = raw
      @max_bytes = max_bytes
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call
      uri = parsed(@url)
      MAX_REDIRECTS.succ.times do
        guard!(uri)
        response, body = get(uri)
        case response
        # Before the redirect branch, and this ordering is load-bearing:
        # 304 *is* a 3xx, so Net::HTTPNotModified is a subclass of
        # Net::HTTPRedirection, and a redirect-first case treats it as a
        # redirect with a missing Location.
        when Net::HTTPNotModified
          # Only reachable when the caller sent a validator, and the whole
          # point of sending one: no body, no parse, no work for either end.
          return page(nil, "", uri, response, not_modified: true)
        when Net::HTTPRedirection
          location = response["location"] or raise Error, "redirect with no destination"
          uri = parsed(URI.join(uri, location).to_s)
        when Net::HTTPSuccess
          return extract(response, body, uri)
        else
          raise Error, "the site answered HTTP #{response.code}"
        end
      end
      raise Error, "too many redirects"
    end

    private
      def parsed(url)
        uri = URI.parse(url)
        raise Error, "only http(s) links work here" unless uri.is_a?(URI::HTTP)
        raise Error, "that link has no host" if uri.host.blank?

        uri
      rescue URI::InvalidURIError
        raise Error, "that doesn't look like a link"
      end

      # Refuse anything that resolves into private/loopback/link-local
      # space — fail closed when the name doesn't resolve at all.
      def guard!(uri)
        addresses = self.class.resolver.getaddresses(uri.host)
        raise Error, "that host doesn't resolve" if addresses.empty?

        addresses.each do |address|
          ip = IPAddr.new(address)
          raise Error, "links into private networks are refused" if BLOCKED_RANGES.any? { |range| range.include?(ip) }
        end
      rescue IPAddr::InvalidAddressError
        raise Error, "that host resolves strangely — refused"
      end

      def get(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        request = Net::HTTP::Get.new(uri, {
          "User-Agent" => USER_AGENT,
          "Accept" => "text/html, application/xhtml+xml, text/*, application/json"
        }.merge(@headers))
        body = nil
        response = http.request(request) { |streaming| body = read_capped(streaming) }
        [ response, body ]
      rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
        raise Error, "couldn't reach the site (#{e.class.name.demodulize})"
      end

      # Just the two validators. Handing back the whole response would hand
      # back Set-Cookie too, and nothing here wants that.
      def page(title, text, uri, response, not_modified: false)
        Page.new(
          title: title, text: text, final_url: uri.to_s, not_modified: not_modified,
          headers: { "etag" => response["etag"], "last-modified" => response["last-modified"] }.compact
        )
      end

      # The cap is enforced while the body arrives, never after. This used to
      # read the whole body and then compare its size, which is no cap at all:
      # a feed that answered with a few hundred megabytes (or a small gzip that
      # inflates to that — Net::HTTP decompresses transparently, and these
      # chunks are the inflated bytes) was held in memory in full before being
      # refused, and the kernel's OOM killer ended the worker mid-job — taking
      # its sibling threads' jobs with it — every time the sweep came round.
      # Binary, the encoding Net::HTTP's own buffered body has, so everything
      # downstream sees the same string it always did.
      def read_capped(response)
        raise Error, TOO_LARGE if response["content-length"].to_i > @max_bytes

        body = String.new(encoding: Encoding::BINARY)
        response.read_body do |chunk|
          body << chunk
          raise Error, TOO_LARGE if body.bytesize > @max_bytes
        end
        body
      end

      def extract(response, body, uri)
        body = body.to_s
        type = content_type(response, body)
        if type.include?("html") && @raw
          page(Nokogiri::HTML(body.scrub).title.to_s.squish.presence, body.scrub, uri, response)
        elsif type.include?("html")
          document = Nokogiri::HTML(body.scrub)
          document.css("script, style, noscript, svg").remove
          page(document.title.to_s.squish.presence,
               document.text.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip, uri, response)
        elsif type.start_with?("text/") || type.include?("json") || type.include?("xml")
          page(nil, body.scrub.strip, uri, response)
        else
          raise Error, "that link is #{type.split(";").first.presence || "not text"} — only pages and text work"
        end
      end

      # A server that sends no Content-Type at all used to be refused
      # outright, which cost the shelf a working feed (Bandcamp Daily sends
      # none). Sniffing is only a *fallback* — a declared type always wins,
      # so this can't be used to talk us into treating a binary as text; it
      # just means a silent server gets read the way `file` would read it.
      def content_type(response, body)
        declared = response["content-type"].to_s
        return declared if declared.present?

        head = body.byteslice(0, 512).to_s.lstrip
        case head
        when /\A<\?xml|\A<(rss|feed|rdf:RDF)\b/i then "application/xml"
        when /\A<(!doctype html|html)\b/i then "text/html"
        when /\A[\[{]/ then "application/json"
        # A calendar export from a server that says nothing about it
        # (D-listing-feeds) — the same silent-server case as above.
        when /\ABEGIN:VCALENDAR\b/i then "text/calendar"
        else ""
        end
      end
  end
end
