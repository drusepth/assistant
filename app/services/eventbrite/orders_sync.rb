# Your own Eventbrite tickets (D-radar-accounts): the v3 API's orders for
# the token's user, each carrying its event. A ticket is a commitment, so
# every one goes onto the calendar through Events::Import, deduped like an
# upload. Eventbrite's API exposes orders and not likes, so this is the
# whole of what it contributes — the account card says so.
#
# Read-only, a private token the user copied from their own developer
# settings, one Bearer header; nothing about the user's places or radius
# is ever sent.
class Eventbrite::OrdersSync
  class Error < StandardError; end

  Result = Struct.new(:imported, :skipped, :error, keyword_init: true)

  ORDERS_URL = "https://www.eventbriteapi.com/v3/users/me/orders/".freeze
  MAX_PAGES = 3

  def initialize(account)
    @account = account
    @user = account.user
  end

  def call
    unless @account.allows?("read")
      raise Error, "Reading your Eventbrite tickets is switched off for this link — re-enable it in Settings to sync."
    end

    events = orders.filter_map { |order| event_for(order["event"]) }
    return Result.new(imported: 0, skipped: 0) if events.empty?

    imported = Events::Import.new(user: @user, events: events).call
    tagged(imported)
    Result.new(imported: imported.imported, skipped: imported.skipped, error: imported.error)
  end

  private
    def orders
      collected = []
      continuation = nil
      MAX_PAGES.times do
        page = fetch(continuation)
        collected.concat(Array(page["orders"]))
        pagination = page["pagination"] || {}
        break unless pagination["has_more_items"] && pagination["continuation"].present?

        continuation = pagination["continuation"]
      end
      collected
    end

    def fetch(continuation)
      params = { "expand" => "event,event.venue", "time_filter" => "current_future" }
      params["continuation"] = continuation if continuation
      url = "#{ORDERS_URL}?#{URI.encode_www_form(params)}"
      page = Web::Fetch.text(url, headers: { "Authorization" => "Bearer #{@account.credentials["token"]}", "Accept" => "application/json" })
      JSON.parse(page.text)
    rescue Web::Fetch::Error => e
      raise Error, "Couldn't read your Eventbrite orders — #{e.message}."
    rescue JSON::ParserError
      raise Error, "Eventbrite answered with something that isn't JSON."
    end

    # An event's start and end come with a timezone of their own; the
    # cancelled ones are left out, as a calendar file's would be.
    def event_for(event)
      return nil unless event.is_a?(Hash)
      return nil if %w[ canceled cancelled deleted ].include?(event["status"].to_s)

      starts_at = parse_time(event["start"])
      return nil unless starts_at

      venue = event["venue"].is_a?(Hash) ? event["venue"] : {}
      Events::Import::ParsedEvent.new(
        title: Listings::Text.clean(event.dig("name", "text"), limit: 300),
        description: [ Listings::Text.clean(event.dig("description", "text")), "Link: #{event["url"]}" ].compact.join("\n\n").presence,
        location: [ venue["name"], venue.dig("address", "localized_address_display") ].compact_blank.join(", ").presence,
        starts_at: starts_at, ends_at: parse_time(event["end"]), all_day: false,
        uid: event["id"].to_s, url: Listings::Text.http_url(event["url"]), status: "CONFIRMED"
      )
    end

    def parse_time(value)
      utc = value.is_a?(Hash) ? value["utc"] : nil
      Time.zone.iso8601(utc.to_s) if utc.present?
    rescue ArgumentError
      nil
    end

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
