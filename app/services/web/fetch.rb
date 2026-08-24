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
    USER_AGENT = "assistant-self-hosted (+https://github.com/drusepth/assistant)".freeze

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
    def initialize(url, headers: {}, raw: false, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      @url = url.to_s.strip
      @headers = headers
      @raw = raw
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call
      uri = parsed(@url)
      MAX_REDIRECTS.succ.times do
        guard!(uri)
        response = get(uri)
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
          return extract(response, uri)
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
        http.request(request)
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

      def extract(response, uri)
        body = response.body.to_s
        raise Error, "the page is too large to read" if body.bytesize > MAX_BYTES

        type = response["content-type"].to_s
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
  end
end
