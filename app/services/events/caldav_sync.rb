# Live calendar pull for the "calendar" linked account (D26): fetches
# iCalendar payloads from the link's CalDAV server and funnels them
# through Events::Import — the same parse/window/dedupe path as an .ics
# upload, so a sync and an upload can never disagree. Mirrors
# People::CarddavSync over the shared Dav::Client.
#
# Read-only by design: it runs only while the link's "read" scope is on
# (checked here, not just in the UI, so a narrowed link fails closed);
# the "write" scope stays reserved for a future push-back.
class Events::CaldavSync
  Error = Dav::Client::Error

  def initialize(account)
    @account = account
  end

  # Returns an Events::Import::Result. Raises Error for anything the user
  # should read (scope off, bad URL, auth, unreachable server).
  def call
    unless @account.allows?("read")
      raise Error, "Reading calendars is switched off for this link — re-enable it in Settings to sync."
    end

    calendars = client.entries(query_body)
    return Events::Import::Result.new(imported: 0, skipped: 0) if calendars.empty?

    Events::Import.new(user: @account.user, content: calendars.join("\n"), filename: "caldav-sync.ics").call
  end

  private
    # The time-range matches the Ics importer's recurrence window, so the
    # server doesn't send decades of history the import would ignore anyway;
    # recurring masters that intersect the window arrive whole and are
    # expanded by the parser exactly as in a file import.
    def query_body
      window_start = (Time.current - Events::Import::Ics::WINDOW_BEHIND).utc.strftime("%Y%m%dT%H%M%SZ")
      window_end = (Time.current + Events::Import::Ics::WINDOW_AHEAD).utc.strftime("%Y%m%dT%H%M%SZ")
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <cal:calendar-query xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop><cal:calendar-data/></d:prop>
          <cal:filter>
            <cal:comp-filter name="VCALENDAR">
              <cal:comp-filter name="VEVENT">
                <cal:time-range start="#{window_start}" end="#{window_end}"/>
              </cal:comp-filter>
            </cal:comp-filter>
          </cal:filter>
        </cal:calendar-query>
      XML
    end

    def client
      Dav::Client.new(
        kind: :caldav,
        server_url: @account.credentials["server_url"],
        username: @account.credentials["username"],
        password: @account.credentials["password"]
      )
    end
end
