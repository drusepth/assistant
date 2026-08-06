require "test_helper"

class Events::CaldavSyncTest < ActiveSupport::TestCase
  setup { @account = linked_accounts(:alice_calendar) }

  def vcalendar(summary, start)
    <<~ICS.strip
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//test//EN
      BEGIN:VEVENT
      UID:#{summary.parameterize}@example.com
      SUMMARY:#{summary}
      DTSTART:#{start}
      DTEND:#{start.sub(/T(\d{2})/) { "T#{format('%02d', Regexp.last_match(1).to_i + 1)}" }}
      LOCATION:Main St Clinic
      END:VEVENT
      END:VCALENDAR
    ICS
  end

  test "walks discovery and imports events from every calendar" do
    start = 2.weeks.from_now.utc.strftime("%Y%m%dT090000Z")
    stub_discovery_chain
    stub_report("https://cal.example.com/cals/home/", [ vcalendar("Dentist", start) ])
    stub_report("https://cal.example.com/cals/work/", [ vcalendar("Team offsite", start) ])

    result = assert_difference("users(:one).events.count", 2) { Events::CaldavSync.new(@account).call }

    assert_equal 2, result.imported
    assert_nil result.error

    dentist = users(:one).events.find_by!(title: "Dentist")
    assert_equal "Main St Clinic", dentist.location
    assert_not dentist.all_day
  end

  test "the calendar query asks only for the import window" do
    stub_discovery_chain
    stub_report("https://cal.example.com/cals/home/", [])
    stub_report("https://cal.example.com/cals/work/", [])

    Events::CaldavSync.new(@account).call

    expected_start = (Time.current - Events::Import::Ics::WINDOW_BEHIND).utc.strftime("%Y%m%dT%H%M")
    assert_requested(:report, "https://cal.example.com/cals/home/") do |request|
      request.body.include?("time-range") && request.body.include?(expected_start)
    end
  end

  test "syncing again skips events already imported" do
    start = 2.weeks.from_now.utc.strftime("%Y%m%dT090000Z")
    stub_discovery_chain
    stub_report("https://cal.example.com/cals/home/", [ vcalendar("Dentist", start) ])
    stub_report("https://cal.example.com/cals/work/", [])

    Events::CaldavSync.new(@account).call
    result = assert_no_difference("Event.count") { Events::CaldavSync.new(@account).call }

    assert_equal 0, result.imported
    assert_equal 1, result.skipped
  end

  test "fails closed when the read scope is switched off" do
    @account.update!(disabled_scopes: [ "read" ])

    error = assert_raises(Events::CaldavSync::Error) { Events::CaldavSync.new(@account).call }
    assert_match "switched off", error.message
  end

  test "the job dispatches by provider and records sync state" do
    start = 2.weeks.from_now.utc.strftime("%Y%m%dT090000Z")
    stub_discovery_chain
    stub_report("https://cal.example.com/cals/home/", [ vcalendar("Dentist", start) ])
    stub_report("https://cal.example.com/cals/work/", [])

    assert_difference("users(:one).events.count", 1) { SyncLinkedAccountJob.perform_now(@account) }

    @account.reload
    assert_not_nil @account.synced_at
    assert_nil @account.sync_error
  end

  test "the job is a no-op for providers without a sync service" do
    SyncLinkedAccountJob.perform_now(linked_accounts(:alice_email))

    assert_nil linked_accounts(:alice_email).reload.synced_at
  end

  private
    def stub_discovery_chain
      stub_propfind("https://cal.example.com/", <<~XML)
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
      stub_propfind("https://cal.example.com/principals/alice/", <<~XML)
        <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/principals/alice/</d:href>
            <d:propstat>
              <d:prop><cal:calendar-home-set><d:href>/cals/</d:href></cal:calendar-home-set></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
      XML
      stub_propfind("https://cal.example.com/cals/", <<~XML)
        <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/cals/</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
          <d:response>
            <d:href>/cals/home/</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
          <d:response>
            <d:href>/cals/work/</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/><cal:calendar/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
      XML
    end

    def stub_propfind(url, xml)
      stub_request(:propfind, url)
        .with(basic_auth: [ "one@example.com", "app-password" ])
        .to_return(status: 207, body: xml)
    end

    def stub_report(url, calendars)
      responses = calendars.map do |ics|
        "<d:response><d:href>/x.ics</d:href><d:propstat><d:prop>" \
          "<cal:calendar-data>#{ics}</cal:calendar-data>" \
          "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
      end
      stub_request(:report, url)
        .with(basic_auth: [ "one@example.com", "app-password" ])
        .to_return(status: 207, body: <<~XML)
          <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
            #{responses.join("\n")}
          </d:multistatus>
        XML
    end
end
