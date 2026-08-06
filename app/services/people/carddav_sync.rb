# Live contacts pull for the "contacts" linked account (D26's first
# consumer): fetches every vCard from the link's CardDAV server and
# funnels them through People::Import — the same normalize/dedupe/
# overflow-to-notes path as a file upload, so a sync and an upload can
# never disagree.
#
# Read-only by design: it runs only while the link's "read" scope is on
# (checked here, not just in the UI, so a narrowed link fails closed);
# the "write" scope stays reserved for a future push-back.
class People::CarddavSync
  Error = Dav::Client::Error

  QUERY_BODY = <<~XML.freeze
    <?xml version="1.0" encoding="utf-8"?>
    <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:prop><card:address-data/></d:prop>
    </card:addressbook-query>
  XML

  def initialize(account)
    @account = account
  end

  # Returns a People::Import::Result. Raises Error for anything the user
  # should read (scope off, bad URL, auth, unreachable server).
  def call
    unless @account.allows?("read")
      raise Error, "Reading contacts is switched off for this link — re-enable it in Settings to sync."
    end

    vcards = client.entries(QUERY_BODY)
    return People::Import::Result.new(imported: 0, skipped: 0) if vcards.empty?

    People::Import.new(user: @account.user, content: vcards.join("\n"), filename: "carddav-sync.vcf").call
  end

  private
    def client
      Dav::Client.new(
        kind: :carddav,
        server_url: @account.credentials["server_url"],
        username: @account.credentials["username"],
        password: @account.credentials["password"]
      )
    end
end
