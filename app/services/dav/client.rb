require "net/http"

# Minimal WebDAV client shared by the linked-account syncs (D26):
# CardDAV (People::CarddavSync) and CalDAV (Events::CaldavSync) are the
# same protocol with different namespaces, so the HTTP mechanics and the
# RFC 6352/4791 discovery walk live here once. Plain Net::HTTP like
# Llm::Client — no vendor gem, auditable lines we own.
#
# Discovery: the pasted URL may be the collection itself (common when
# copied from a provider's settings page), or an account root we walk via
# current-user-principal → home-set → the collections under it, with a
# /.well-known retry for servers that hide discovery there (iCloud).
class Dav::Client
  class Error < StandardError; end

  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 60

  KINDS = {
    carddav: {
      urn: "urn:ietf:params:xml:ns:carddav",
      home_set: "addressbook-home-set",
      collection: "addressbook",
      data: "address-data",
      well_known: "/.well-known/carddav",
      noun: "contacts"
    },
    caldav: {
      urn: "urn:ietf:params:xml:ns:caldav",
      home_set: "calendar-home-set",
      collection: "calendar",
      data: "calendar-data",
      well_known: "/.well-known/caldav",
      noun: "calendar"
    }
  }.freeze

  class Propfind < Net::HTTPRequest
    METHOD = "PROPFIND"
    REQUEST_HAS_BODY = true
    RESPONSE_HAS_BODY = true
  end

  class Report < Net::HTTPRequest
    METHOD = "REPORT"
    REQUEST_HAS_BODY = true
    RESPONSE_HAS_BODY = true
  end

  DISCOVER_BODY = <<~XML.freeze
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop><d:resourcetype/><d:current-user-principal/></d:prop>
    </d:propfind>
  XML

  LIST_BODY = <<~XML.freeze
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop><d:resourcetype/></d:prop>
    </d:propfind>
  XML

  def initialize(kind:, server_url:, username:, password:)
    @config = KINDS.fetch(kind)
    @server_url = server_url
    @username = username
    @password = password
    @ns = { "d" => "DAV:", "x" => @config[:urn] }
  end

  # Runs the REPORT query against every discovered collection and returns
  # the raw payloads (vCards / iCalendar documents) as strings.
  def entries(report_body)
    collection_urls.flat_map do |url|
      doc = dav_request(url, Report, depth: 1, body: report_body)
      doc.xpath("//x:#{@config[:data]}", @ns).map { |node| node.text.strip }.reject(&:empty?)
    end
  end

  private
    def collection_urls
      base = server_uri
      doc = discovery_document(base)
      return [ base ] if doc.xpath("//d:response/d:propstat//d:resourcetype/x:#{@config[:collection]}", @ns).any?

      principal = first_href(doc, "//d:current-user-principal/d:href") or
        raise Error, "The server didn't identify your account — check the server URL."
      home_doc = propfind(base + principal, 0, home_body)
      home = first_href(home_doc, "//x:#{@config[:home_set]}/d:href") or
        raise Error, "The server didn't report a #{@config[:collection]} location for your account."

      list = propfind(base + home, 1, LIST_BODY)
      urls = list.xpath("//d:response", @ns)
        .select { |response| response.xpath(".//d:resourcetype/x:#{@config[:collection]}", @ns).any? }
        .map { |response| base + response.at_xpath("d:href", @ns).text.strip }
      raise Error, "No #{@config[:noun]} collections found for this account." if urls.empty?
      urls
    end

    # If the pasted URL won't discover, retry at the well-known path before
    # giving up on the original error (the more specific message of the two).
    def discovery_document(base)
      propfind(base, 0, DISCOVER_BODY)
    rescue Error => original
      begin
        propfind(base + @config[:well_known], 0, DISCOVER_BODY)
      rescue Error
        raise original
      end
    end

    def home_body
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:x="#{@config[:urn]}">
          <d:prop><x:#{@config[:home_set]}/></d:prop>
        </d:propfind>
      XML
    end

    def propfind(uri, depth, body)
      dav_request(uri, Propfind, depth: depth, body: body)
    end

    def dav_request(uri, klass, depth:, body:, redirects: 3)
      request = klass.new(uri)
      request.basic_auth(@username.to_s, @password.to_s)
      request["Depth"] = depth.to_s
      request["Content-Type"] = "application/xml; charset=utf-8"
      request.body = body

      response = Net::HTTP.start(uri.hostname, uri.port,
        use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      case response
      when Net::HTTPRedirection
        raise Error, "The server redirected too many times." if redirects.zero?
        dav_request(uri + response["Location"], klass, depth: depth, body: body, redirects: redirects - 1)
      when Net::HTTPUnauthorized, Net::HTTPForbidden
        raise Error, "The server rejected the username or password — most providers need an app-specific password."
      when Net::HTTPSuccess # includes 207 Multi-Status
        Nokogiri::XML(response.body)
      else
        raise Error, "The #{@config[:noun]} server returned #{response.code}."
      end
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "Couldn't reach the #{@config[:noun]} server: #{e.message}"
    end

    def server_uri
      uri = URI(@server_url.to_s.strip)
      raise Error, "The server URL must start with https:// or http://." unless uri.is_a?(URI::HTTP)
      uri
    rescue URI::InvalidURIError
      raise Error, "That server URL doesn't look valid."
    end

    def first_href(doc, xpath)
      doc.at_xpath(xpath, @ns)&.text&.strip.presence
    end
end
