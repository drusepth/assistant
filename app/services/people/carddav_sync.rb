require "net/http"

# The first linked-account consumer (D21): pulls contacts live from the
# "contacts" link's CardDAV server and funnels every vCard through
# People::Import — the same normalize/dedupe/overflow-to-notes path as a
# file upload, so a sync and an upload can never disagree.
#
# Read-only by design: it runs only while the link's "read" scope is on
# (checked here, not just in the UI, so a narrowed link fails closed), and
# the "write" scope stays reserved for a future push-back. Plain Net::HTTP
# like Llm::Client — no vendor gem, auditable lines we own.
#
# Discovery follows RFC 6352: the pasted URL may be the address book
# itself, or an account root we walk via current-user-principal →
# addressbook-home-set → the addressbook collections under it, with a
# /.well-known/carddav retry for servers that hide discovery there.
class People::CarddavSync
  class Error < StandardError; end

  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 60
  NS = { "d" => "DAV:", "card" => "urn:ietf:params:xml:ns:carddav" }.freeze

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

  HOME_BODY = <<~XML.freeze
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:prop><card:addressbook-home-set/></d:prop>
    </d:propfind>
  XML

  LIST_BODY = <<~XML.freeze
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop><d:resourcetype/></d:prop>
    </d:propfind>
  XML

  QUERY_BODY = <<~XML.freeze
    <?xml version="1.0" encoding="utf-8"?>
    <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:prop><card:address-data/></d:prop>
    </card:addressbook-query>
  XML

  def initialize(account)
    @account = account
    @credentials = account.credentials
  end

  # Returns a People::Import::Result. Raises Error for anything the user
  # should read (scope off, bad URL, auth, unreachable server).
  def call
    unless @account.allows?("read")
      raise Error, "Reading contacts is switched off for this link — re-enable it in Settings to sync."
    end

    vcards = addressbook_urls.flat_map { |url| fetch_vcards(url) }
    return People::Import::Result.new(imported: 0, skipped: 0) if vcards.empty?

    People::Import.new(user: @account.user, content: vcards.join("\n"), filename: "carddav-sync.vcf").call
  end

  private
    def addressbook_urls
      base = server_uri
      doc = discovery_document(base)
      # The pasted URL may already be an address book — common when copied
      # from a provider's settings page — so no walking needed.
      return [ base ] if doc.xpath("//d:response/d:propstat//d:resourcetype/card:addressbook", NS).any?

      principal = first_href(doc, "//d:current-user-principal/d:href") or
        raise Error, "The server didn't identify your account — check the server URL."
      home_doc = propfind(base + principal, 0, HOME_BODY)
      home = first_href(home_doc, "//card:addressbook-home-set/d:href") or
        raise Error, "The server didn't report an address-book location for your account."

      list = propfind(base + home, 1, LIST_BODY)
      urls = list.xpath("//d:response", NS)
        .select { |response| response.xpath(".//d:resourcetype/card:addressbook", NS).any? }
        .map { |response| base + response.at_xpath("d:href", NS).text.strip }
      raise Error, "No address books found for this account." if urls.empty?
      urls
    end

    # Servers like iCloud only answer discovery at the well-known path; if
    # the pasted URL won't discover, retry there before giving up on the
    # original error (the more specific message of the two).
    def discovery_document(base)
      propfind(base, 0, DISCOVER_BODY)
    rescue Error => original
      begin
        propfind(base + "/.well-known/carddav", 0, DISCOVER_BODY)
      rescue Error
        raise original
      end
    end

    def fetch_vcards(uri)
      doc = dav_request(uri, Report, depth: 1, body: QUERY_BODY)
      doc.xpath("//card:address-data", NS).map { |node| node.text.strip }.reject(&:empty?)
    end

    def propfind(uri, depth, body)
      dav_request(uri, Propfind, depth: depth, body: body)
    end

    def dav_request(uri, klass, depth:, body:, redirects: 3)
      request = klass.new(uri)
      request.basic_auth(@credentials["username"].to_s, @credentials["password"].to_s)
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
        raise Error, "The contacts server returned #{response.code}."
      end
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "Couldn't reach the contacts server: #{e.message}"
    end

    def server_uri
      uri = URI(@credentials["server_url"].to_s.strip)
      raise Error, "The server URL must start with https:// or http://." unless uri.is_a?(URI::HTTP)
      uri
    rescue URI::InvalidURIError
      raise Error, "That server URL doesn't look valid."
    end

    def first_href(doc, xpath)
      doc.at_xpath(xpath, NS)&.text&.strip.presence
    end
end
