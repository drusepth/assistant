module Watcher
  # The section's cheapest delight (docs/PEOPLE.md §5): birthdays are
  # already in the data — imports carry them — so a circle birthday within
  # three weeks earns a heads-up whose accept lands a gift task (due a week
  # ahead) and the day itself on the calendar. Circle-scoped, because a
  # synced address book must not spray acquaintances' birthdays.
  class BirthdayRadar < Base
    self.section_slugs = %w[ people ]

    LEAD = 21
    GIFT_LEAD = 7

    def scan
      user.people.circle.birthday_within(LEAD).each do |person|
        date = person.next_birthday
        propose(
          fingerprint: "person:#{person.id}/#{date.year}",
          kind: :heads_up,
          title: "#{person.name}'s birthday is #{date.strftime("%B %-d")}",
          body: body_for(date),
          action: {
            "accept_label" => "Get ready",
            "task" => { "title" => "Get a birthday gift for #{person.name}",
                        "due_on" => [ date - GIFT_LEAD, Date.current ].max.iso8601 },
            "event" => { "title" => "#{person.name}'s birthday", "starts_at" => date.iso8601, "all_day" => true },
            # "Get ready" stops meaning anything once the day has gone by;
            # the suggestion retires the morning after rather than sitting
            # in Attend as a reproach (D-suggestion-lifecycle).
            "expires_on" => date.iso8601
          },
          sections: (self.class.section_slugs + person.sections.map(&:slug)).uniq
        )
      end
    end

    # They left the circle, or the record is gone. (The day itself is
    # handled by `expires_on`, which needs no watcher code.)
    def resolved?(suggestion)
      return false unless (id = subject_id(suggestion, "person"))

      user.people.circle.find_by(id: id).nil?
    end

    private
      def body_for(date)
        days = (date - Date.current).to_i
        lead = days.zero? ? "That's today!" : "#{days} #{"day".pluralize(days)} out."
        "#{lead} Accepting puts it on your calendar with a gift reminder ahead of it."
      end
  end
end
