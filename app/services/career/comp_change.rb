module Career
  # The comp timeline (D-career-signal): a compensation change is an ordinary
  # Career-tagged all-day Event wearing a recognizable title prefix, so the
  # one-tap manual log and pay-stub extraction write to one timeline and the
  # raise-cadence watcher reads it with plain SQL. Manual wins conflicts by
  # construction — an extracted change the user disagrees with is an Event
  # they can edit or delete like any other.
  module CompChange
    EVENT_PREFIX = "Comp change:".freeze

    module_function

    def log!(user:, summary:, on: Date.current, description: nil)
      summary = summary.to_s.squish
      raise ArgumentError, "a comp change needs a description" if summary.blank?

      event = user.events.create!(
        title: "#{EVENT_PREFIX} #{summary}",
        starts_at: on.in_time_zone, all_day: true, description: description
      )
      event.sections = Section.where(slug: "career")
      event
    end

    def scope(user)
      user.events.where("title LIKE ?", "#{EVENT_PREFIX}%")
    end

    # When compensation last moved — what raise cadence measures from.
    def latest_on(user)
      scope(user).maximum(:starts_at)&.to_date
    end
  end
end
