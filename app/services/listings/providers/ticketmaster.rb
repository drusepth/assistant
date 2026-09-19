module Listings
  module Providers
    # The opt-in search (D-listing-feeds §8): Ticketmaster's Discovery API,
    # queried by a place's point, radius and the river's horizon. Concerts,
    # sports, theatre — the paid-ticket world no city calendar covers, and
    # the one way a trip destination has anything on its first day.
    #
    # It is a keyed API answering with structured events — deterministic
    # HTTP, not a model browsing — but the request names the place's
    # coordinates, which is why it is off by default, per place, and the
    # switch says so out loud. A category the answer carries ("Music /
    # Jazz") rides the description as context for the model and decides
    # nothing itself.
    class Ticketmaster
      ENDPOINT = "https://app.ticketmaster.com/discovery/v2/events.json".freeze
      PAGE_SIZE = 100
      MAX_PAGES = 3
      GONE = %w[ cancelled canceled postponed ].freeze

      def self.call(source) = new(source).call

      def initialize(source)
        @source = source
        @place = source.place
        @key = source.credentials.to_h["api_key"].to_s
      end

      # Items, or raises Web::Fetch::Error so Refresh records it on the row.
      def call
        raise Web::Fetch::Error, "no Ticketmaster key on this source" if @key.blank?

        (0...MAX_PAGES).flat_map { |page| events_on(page) }.compact.uniq(&:uid)
      end

      private
        def events_on(page)
          body = JSON.parse(Web::Fetch.text(url(page), headers: { "Accept" => "application/json" }).text)
          events = body.dig("_embedded", "events") || []
          return [] if events.empty?

          items = events.filter_map { |event| item_for(event) }
          total_pages = body.dig("page", "totalPages").to_i
          page + 1 < total_pages ? items : items.push(nil)
        rescue JSON::ParserError
          raise Web::Fetch::Error, "Ticketmaster answered with something that isn't JSON"
        end

        def url(page)
          params = {
            "apikey" => @key, "latlong" => "#{@place.latitude},#{@place.longitude}",
            "radius" => @place.radius_km, "unit" => "km", "size" => PAGE_SIZE, "page" => page,
            "sort" => "date,asc", "startDateTime" => Time.current.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "endDateTime" => Happening::HORIZON.from_now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
          }
          "#{ENDPOINT}?#{URI.encode_www_form(params)}"
        end

        def item_for(event)
          return nil if GONE.include?(event.dig("dates", "status", "code").to_s)

          starts_at, all_day = start_of(event["dates"] || {})
          title = Text.clean(event["name"], limit: 300)
          return nil if starts_at.nil? || title.blank?

          venue = Array(event.dig("_embedded", "venues")).first || {}
          lat = Float(venue.dig("location", "latitude").to_s, exception: false)
          lng = Float(venue.dig("location", "longitude").to_s, exception: false)
          category = Array(event["classifications"]).first&.then { |c| [ c.dig("segment", "name"), c.dig("genre", "name") ].compact_blank.uniq.join(" / ") }

          Item.build(
            uid: "tm:#{event["id"]}", title: title,
            description: Text.clean([ event["info"], event["pleaseNote"], ("Ticketmaster: #{category}" if category.present?) ].compact_blank.join(" ")),
            location: Text.clean([ venue["name"], venue.dig("city", "name") ].compact_blank.join(", "), limit: 500),
            url: Text.http_url(event["url"]), latitude: lat, longitude: lng,
            starts_at: starts_at, all_day: all_day
          )
        end

        def start_of(dates)
          start = dates["start"] || {}
          if start["dateTime"].present?
            [ Time.zone.iso8601(start["dateTime"]), false ]
          elsif start["localDate"].present?
            [ Date.iso8601(start["localDate"]).in_time_zone, true ]
          else
            [ nil, false ]
          end
        rescue ArgumentError, Date::Error
          [ nil, false ]
        end
    end
  end
end
