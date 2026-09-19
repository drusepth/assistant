module Listings
  module Parse
    # An iCalendar feed as listing items (D-listing-feeds). The parsing is
    # `Events::Import::Ics`'s — folding, TZID, all-day spans, DURATION,
    # cancelled events, RRULE expansion inside a window, EXDATE and
    # RECURRENCE-ID — and this only decides what a row is called.
    #
    # An expanded occurrence shares its master's UID, so its own uid gets
    # the start appended and the bare UID becomes the `series_uid` that lets
    # a weekly meetup be judged once. A one-off keeps the bare UID, so a
    # publisher moving its time updates the row in place.
    class Ics
      def self.handles?(body) = body.to_s.lstrip.start_with?("BEGIN:VCALENDAR")

      def self.call(body) = new(body).call

      def initialize(body)
        @body = body.to_s
      end

      def call
        return nil unless self.class.handles?(@body)

        Events::Import::Ics.new(@body).events.filter_map { |event| item_for(event) }
      end

      private
        def item_for(event)
          return nil if event.title.blank? || event.starts_at.blank?

          series = event.uid.presence || "#{event.title}@#{event.starts_at.to_i}"
          uid = event.recurring ? "#{series}/#{event.starts_at.to_i}" : series
          lat, lng = event.geo
          # The calendar import folds the link into the description because
          # an Event has nowhere else to put it; a happening has a column.
          description = event.description.to_s.sub(/^Link: #{Regexp.escape(event.url.to_s)}$/, "") if event.url.present?

          Item.build(
            uid: uid.truncate(500, omission: ""), series_uid: series.truncate(500, omission: ""),
            title: Text.clean(event.title, limit: 300),
            description: Text.clean(description || event.description),
            location: Text.clean(event.location, limit: 500),
            url: Text.http_url(event.url),
            latitude: lat, longitude: lng,
            starts_at: event.starts_at, ends_at: event.ends_at, all_day: !!event.all_day
          )
        end
    end
  end
end
