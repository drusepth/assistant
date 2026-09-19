# Your own Meetup calendar (D-radar-accounts): the private iCal export a
# member can copy from meetup.com. Read-only, and split three ways by what
# the export says about each event:
#
#   - CONFIRMED (or no status) is an RSVP — already your event, so it goes
#     onto the calendar through Events::Import exactly as a CalDAV sync
#     does, tagged Hobbies and auto-sorted into a lens like any event;
#   - TENTATIVE is a "maybe" — a happening you already judged, recorded
#     under the nearest place with `provenance: saved`, never read by the
#     model, nudged inside the lead time (Radar::Saved);
#   - the groups you typed on the account are offered as calendars under
#     each place (Radar::Groups) — never followed for you.
#
# Fetched through Web::Fetch like any stranger's calendar (SSRF guard, size
# cap), because the link is one the user pasted.
class Meetup::CalendarSync
  class Error < StandardError; end

  Result = Struct.new(:imported, :skipped, :saved, :error, keyword_init: true)

  def initialize(account)
    @account = account
    @user = account.user
  end

  def call
    unless @account.allows?("read")
      raise Error, "Reading your Meetup calendar is switched off for this link — re-enable it in Settings to sync."
    end

    parsed = fetch
    going, maybe = parsed.partition { |event| event.status != "TENTATIVE" }

    imported = going.any? ? Events::Import.new(user: @user, events: going).call : Events::Import::Result.new(imported: 0, skipped: 0)
    saved = Radar::Saved.record!(@user, maybe.filter_map { |event| item_for(event) }, account: @account)
    tagged(imported)

    Result.new(imported: imported.imported, skipped: imported.skipped, saved: saved.size, error: imported.error)
  end

  private
    def fetch
      url = @account.credentials["calendar_url"].to_s.sub(%r{\Awebcals?://}i, "https://")
      page = Web::Fetch.raw(url, headers: { "Accept" => "text/calendar" }, max_bytes: Listings::Discover::MAX_BYTES)
      events = Events::Import::Ics.new(page.text).events
      raise Error, "That link isn't a calendar — copy the iCal export link from your Meetup calendar." if events.empty? && !page.text.lstrip.start_with?("BEGIN:VCALENDAR")

      events.select { |event| event.title.present? && event.starts_at.present? }
    rescue Web::Fetch::Error => e
      raise Error, "Couldn't read your Meetup calendar — #{e.message}."
    end

    def item_for(event)
      lat, lng = event.geo
      Listings::Item.build(
        uid: (event.uid.presence || "#{event.title}@#{event.starts_at.to_i}").truncate(500, omission: ""),
        title: Listings::Text.clean(event.title, limit: 300),
        description: Listings::Text.clean(event.description), location: Listings::Text.clean(event.location, limit: 500),
        url: Listings::Text.http_url(event.url), latitude: lat, longitude: lng,
        starts_at: event.starts_at, ends_at: event.ends_at, all_day: !!event.all_day
      )
    end

    # Newly imported RSVPs are hobby things until the model files them
    # finer — the same quick-add-then-sort shape every primitive uses.
    def tagged(result)
      return unless result.imported.to_i.positive?

      hobbies = Section.find_by(slug: "hobbies") or return
      @user.events.where(created_at: 1.minute.ago..).left_joins(:section_taggings)
        .where(section_taggings: { id: nil }).find_each do |event|
        event.sections = [ hobbies ]
        event.enqueue_auto_sort!
      end
    end
end
