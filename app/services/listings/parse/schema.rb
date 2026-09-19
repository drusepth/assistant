module Listings
  module Parse
    # A web page's schema.org structured data as listing items
    # (D-listing-feeds). Only the JSON-LD blocks are read — the form Google's
    # event search requires, so publishers keep it correct — and the page's
    # prose is never read for dates or names. Parsing a block a publisher
    # wrote for machines is deterministic, which keeps this on the right
    # side of D-no-keyword-logic.
    #
    # Two shapes: `Event` and its subtypes (a venue's shows, a Meetup group's
    # page, an Eventbrite organizer, a city calendar), and — for the
    # volunteer half — `JobPosting` marked `VOLUNTEER`, which is the
    # documented way to publish a role that is looking for people.
    class Schema
      EVENT_TYPES = %w[
        Event BusinessEvent ChildrensEvent ComedyEvent CourseInstance DanceEvent DeliveryEvent
        EducationEvent EventSeries ExhibitionEvent Festival FoodEvent Hackathon LiteraryEvent
        MusicEvent PublishingEvent SaleEvent ScreeningEvent SocialEvent SportsEvent TheaterEvent
        VisualArtsEvent
      ].to_set.freeze
      # Cancelled and postponed events say so in their status; both are
      # dropped, and the withdrawal rule in Refresh retires the row.
      GONE_STATUSES = %w[ EventCancelled EventPostponed ].freeze
      MAX_ITEMS = 500

      def self.handles?(body) = body.to_s.include?("application/ld+json")

      def self.call(body) = new(body).call

      def initialize(body)
        @body = body.to_s
      end

      # nil when the page carries no structured data at all — the signal
      # discovery uses to say "this page is not a source".
      def call
        return nil unless self.class.handles?(@body)

        nodes = blocks.flat_map { |block| nodes_in(block) }
        items = nodes.filter_map { |node| item_for(node) }.uniq(&:uid).first(MAX_ITEMS)
        items.any? || nodes.any? ? items : nil
      end

      private
        def blocks
          Nokogiri::HTML(@body).css('script[type="application/ld+json"]').filter_map do |script|
            JSON.parse(script.text)
          rescue JSON::ParserError
            nil
          end
        end

        # A block is an object, an array, or an object carrying a @graph; an
        # EventSeries carries its instances in subEvent. Walked, not
        # searched: only the shapes the standard names are read.
        def nodes_in(block, depth = 0)
          return [] if depth > 3

          case block
          when Array then block.flat_map { |entry| nodes_in(entry, depth + 1) }
          when Hash
            own = typed?(block) ? [ block ] : []
            nested = Array(block["@graph"]) + Array(block["subEvent"]) + Array(block["itemListElement"]).map { |entry| entry.is_a?(Hash) ? entry["item"] || entry : entry }
            own + nested.flat_map { |entry| nodes_in(entry, depth + 1) }
          else []
          end
        end

        def types(node) = Array(node["@type"]).map { |type| type.to_s.split("/").last }

        def typed?(node) = node.is_a?(Hash) && (types(node) & (EVENT_TYPES.to_a + %w[ JobPosting ])).any?

        def item_for(node)
          return job_item(node) if types(node).include?("JobPosting")

          status = node["eventStatus"].to_s.split("/").last
          return nil if GONE_STATUSES.include?(status)

          starts_at, all_day = parse_when(node["startDate"])
          title = Text.clean(node["name"], limit: 300)
          return nil if starts_at.nil? || title.blank?

          ends_at, = parse_when(node["endDate"])
          url = Text.http_url(node["url"])
          place = location(node["location"])

          Item.build(
            uid: uid_for(node, url, title, starts_at), title: title,
            description: Text.clean(node["description"]), location: place[:name], url: url,
            latitude: place[:latitude], longitude: place[:longitude],
            starts_at: starts_at, ends_at: ends_at, all_day: all_day
          )
        end

        # schema.org's documented way to say a role is unpaid.
        def job_item(node)
          return nil unless Array(node["employmentType"]).any? { |type| type.to_s.casecmp?("VOLUNTEER") }

          title = Text.clean(node["title"], limit: 300)
          return nil if title.blank?

          url = Text.http_url(node["url"])
          org = node["hiringOrganization"].is_a?(Hash) ? Text.clean(node["hiringOrganization"]["name"], limit: 200) : nil
          place = location(node["jobLocation"])
          expires = Date.iso8601(node["validThrough"].to_s.first(10)) rescue nil

          Item.build(
            uid: uid_for(node, url, title, nil), kind: "opening", title: title,
            description: Text.clean(node["description"]),
            location: [ org, place[:name] ].compact.uniq.join(" — ").presence, url: url,
            latitude: place[:latitude], longitude: place[:longitude], expires_on: expires
          )
        end

        # The publisher's own identifier when it gives one; the link, which
        # is the next best; and the title-plus-start only when it gives
        # neither.
        def uid_for(node, url, title, starts_at)
          id = node["@id"].to_s.strip.presence || url
          (id || "#{title}@#{starts_at.to_i}").truncate(500, omission: "")
        end

        # A location is a Place, a VirtualLocation, a bare string, or an
        # array of those; the first physical one wins.
        def location(value)
          # Not Array(): that splits a Hash into pairs.
          entries = value.is_a?(Array) ? value : [ value ]
          entries.each do |entry|
            case entry
            when String then return { name: Text.clean(entry, limit: 500) }
            when Hash
              next if types(entry).include?("VirtualLocation")

              geo = entry["geo"].is_a?(Hash) ? entry["geo"] : {}
              lat = Float(geo["latitude"].to_s, exception: false)
              lng = Float(geo["longitude"].to_s, exception: false)
              lat = lng = nil unless lat && lng && lat.abs <= 90 && lng.abs <= 180
              return { name: place_name(entry), latitude: lat, longitude: lng }
            end
          end
          entries.any? { |entry| entry.is_a?(Hash) && types(entry).include?("VirtualLocation") } ? { name: "Online" } : {}
        end

        def place_name(entry)
          address = entry["address"]
          address = [ address["streetAddress"], address["addressLocality"] ].compact_blank.join(", ") if address.is_a?(Hash)
          Text.clean([ entry["name"], address ].compact_blank.uniq.join(", "), limit: 500)
        end

        # ISO 8601, as the standard requires; a date-only value is an
        # all-day event. Anything else is no date, and no date is no row.
        def parse_when(value)
          value = value.to_s.strip
          return [ nil, false ] if value.blank?
          return [ Date.iso8601(value).in_time_zone, true ] if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          [ Time.zone.iso8601(value), false ]
        rescue ArgumentError, Date::Error
          [ nil, false ]
        end
    end
  end
end
