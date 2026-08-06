require "test_helper"

class People::CarddavSyncTest < ActiveSupport::TestCase
  setup { @account = linked_accounts(:alice_contacts) }

  VCARD_MARIA = "BEGIN:VCARD\nVERSION:3.0\nFN:Maria Rivera\nTEL;TYPE=CELL:+1 (555) 010-2000\nEMAIL:maria@example.com\nEND:VCARD"
  VCARD_SAM = "BEGIN:VCARD\nVERSION:3.0\nFN:Sam Okafor\nTEL:+1 (555) 010-3000\nEND:VCARD"

  test "walks discovery and imports every vCard from every address book" do
    stub_discovery_chain
    stub_report("https://dav.example.com/books/personal/", [ VCARD_MARIA ])
    stub_report("https://dav.example.com/books/work/", [ VCARD_SAM ])

    result = assert_difference("users(:one).people.count", 2) { People::CarddavSync.new(@account).call }

    assert_equal 2, result.imported
    assert_nil result.error

    maria = users(:one).people.find_by!(name: "Maria Rivera")
    assert_equal "+1 (555) 010-2000", maria.phone
    assert_equal "maria@example.com", maria.email
    assert_equal [ "people" ], maria.sections.map(&:slug)
  end

  test "a pasted URL that is itself an address book skips discovery" do
    stub_propfind("https://dav.example.com/", <<~XML)
      <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
        <d:response>
          <d:href>/</d:href>
          <d:propstat>
            <d:prop><d:resourcetype><d:collection/><card:addressbook/></d:resourcetype></d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
      </d:multistatus>
    XML
    stub_report("https://dav.example.com/", [ VCARD_MARIA ])

    result = People::CarddavSync.new(@account).call

    assert_equal 1, result.imported
  end

  test "syncing again skips contacts already in People" do
    stub_discovery_chain
    stub_report("https://dav.example.com/books/personal/", [ VCARD_MARIA ])
    stub_report("https://dav.example.com/books/work/", [ VCARD_SAM ])

    People::CarddavSync.new(@account).call
    result = assert_no_difference("Person.count") { People::CarddavSync.new(@account).call }

    assert_equal 0, result.imported
    assert_equal 2, result.skipped
  end

  test "an empty address book is a successful sync of nothing" do
    stub_discovery_chain
    stub_report("https://dav.example.com/books/personal/", [])
    stub_report("https://dav.example.com/books/work/", [])

    result = People::CarddavSync.new(@account).call

    assert_equal 0, result.imported
    assert_nil result.error
  end

  test "fails closed when the read scope is switched off" do
    @account.update!(disabled_scopes: [ "read" ])

    error = assert_raises(People::CarddavSync::Error) { People::CarddavSync.new(@account).call }
    assert_match "switched off", error.message
  end

  test "bad credentials become a readable error" do
    stub_request(:propfind, "https://dav.example.com/").to_return(status: 401)
    stub_request(:propfind, "https://dav.example.com/.well-known/carddav").to_return(status: 401)

    error = assert_raises(People::CarddavSync::Error) { People::CarddavSync.new(@account).call }
    assert_match "app-specific password", error.message
  end

  test "an unreachable server becomes a readable error" do
    stub_request(:propfind, "https://dav.example.com/").to_raise(SocketError.new("getaddrinfo failed"))
    stub_request(:propfind, "https://dav.example.com/.well-known/carddav").to_raise(SocketError.new("getaddrinfo failed"))

    error = assert_raises(People::CarddavSync::Error) { People::CarddavSync.new(@account).call }
    assert_match "Couldn't reach", error.message
  end

  test "discovery falls back to the well-known path" do
    stub_request(:propfind, "https://dav.example.com/").to_return(status: 404)
    stub_propfind("https://dav.example.com/.well-known/carddav", principal_xml)
    stub_propfind("https://dav.example.com/principals/alice/", home_set_xml)
    stub_propfind("https://dav.example.com/books/", book_list_xml)
    stub_report("https://dav.example.com/books/personal/", [ VCARD_MARIA ])
    stub_report("https://dav.example.com/books/work/", [ VCARD_SAM ])

    assert_equal 2, People::CarddavSync.new(@account).call.imported
  end

  test "the job records sync state on the link" do
    stub_discovery_chain
    stub_report("https://dav.example.com/books/personal/", [ VCARD_MARIA ])
    stub_report("https://dav.example.com/books/work/", [])

    SyncLinkedAccountJob.perform_now(@account)

    @account.reload
    assert_not_nil @account.synced_at
    assert_nil @account.sync_error
  end

  test "the job records a failed sync without touching synced_at" do
    stub_request(:propfind, "https://dav.example.com/").to_return(status: 401)
    stub_request(:propfind, "https://dav.example.com/.well-known/carddav").to_return(status: 401)

    SyncLinkedAccountJob.perform_now(@account)

    @account.reload
    assert_nil @account.synced_at
    assert_match "app-specific password", @account.sync_error
  end

  private
    def principal_xml
      <<~XML
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/</d:href>
            <d:propstat>
              <d:prop>
                <d:resourcetype><d:collection/></d:resourcetype>
                <d:current-user-principal><d:href>/principals/alice/</d:href></d:current-user-principal>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
      XML
    end

    def home_set_xml
      <<~XML
        <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:response>
            <d:href>/principals/alice/</d:href>
            <d:propstat>
              <d:prop><card:addressbook-home-set><d:href>/books/</d:href></card:addressbook-home-set></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
      XML
    end

    def book_list_xml
      <<~XML
        <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:response>
            <d:href>/books/</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
          <d:response>
            <d:href>/books/personal/</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/><card:addressbook/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
          <d:response>
            <d:href>/books/work/</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/><card:addressbook/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
      XML
    end

    def stub_discovery_chain
      stub_propfind("https://dav.example.com/", principal_xml)
      stub_propfind("https://dav.example.com/principals/alice/", home_set_xml)
      stub_propfind("https://dav.example.com/books/", book_list_xml)
    end

    def stub_propfind(url, xml)
      stub_request(:propfind, url)
        .with(basic_auth: [ "one@example.com", "app-password" ])
        .to_return(status: 207, body: xml)
    end

    def stub_report(url, vcards)
      responses = vcards.map do |vcard|
        "<d:response><d:href>/x.vcf</d:href><d:propstat><d:prop>" \
          "<card:address-data>#{vcard}</card:address-data>" \
          "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
      end
      stub_request(:report, url)
        .with(basic_auth: [ "one@example.com", "app-password" ])
        .to_return(status: 207, body: <<~XML)
          <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
            #{responses.join("\n")}
          </d:multistatus>
        XML
    end
end
