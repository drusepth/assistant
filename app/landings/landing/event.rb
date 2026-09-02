module Landing
  # The workhorse: visits, deadlines, renewals, due dates. A past visit is
  # what the care radar counts; a future date is what the calendar and the
  # renewal radar give lead time to.
  class Event < Base
    self.description = "an appointment, visit, deadline or renewal date the document states"
    self.produces = "events"

    field :title, "short; names whom it is about, e.g. \"Rex — vaccinations\"", required: true
    field :on, "the date", type: :date, required: true
    field :time, "only when the document states a time of day", type: :time
    field :location
    field :description, "anything else the document says about it", type: :text

    def land!(attributes, sections:)
      on = Date.iso8601(attributes["on"])
      starts_at = if attributes["time"].present?
        hour, minute = attributes["time"].split(":").map(&:to_i)
        on.in_time_zone.change(hour: hour, min: minute)
      else
        on.in_time_zone
      end

      event = user.events.create!(
        title: attributes["title"], starts_at: starts_at, all_day: attributes["time"].blank?,
        location: attributes["location"], description: attributes["description"]
      )
      tag(event, sections)
    end

    def duplicate_of(attributes)
      on = parsed_date(attributes["on"]) or return nil

      ::Event.visible_to(user).where(starts_at: on.in_time_zone.all_day)
        .where("LOWER(events.title) = ?", attributes["title"].to_s.downcase).first
    end

    def preview(attributes)
      Preview.new(kind: kind, title: attributes["title"], detail: attributes["description"], date: attributes["on"])
    end

    private
      def key_fields = %w[ title on ]
  end
end
