module Watcher
  # Renewals go better with lead time: an upcoming event whose title smells
  # like a renewal/expiry — or a medication refill (docs/HEALTH.md §7) —
  # gets a heads-up while there's still room to act. One suggestion per
  # event, ever — dismissing it settles the matter.
  class RenewalRadar < Base
    self.section_slugs = %w[ money rights health ]

    WINDOW = 60.days
    LEAD_TIME = 14.days
    KEYWORDS = %w[ renew expir lease refill ].freeze

    def scan
      matches.find_each do |event|
        act_by = [ event.starts_at.to_date - LEAD_TIME, Date.current ].max
        propose(
          fingerprint: "event:#{event.id}",
          kind: :heads_up,
          title: "“#{event.title}” is coming up on #{event.starts_at.strftime("%B %-d")}",
          body: "Deadlines like this go better with lead time — decide and act before the date decides for you.",
          action: { "task" => { "title" => "Sort out: #{event.title}", "due_on" => act_by.iso8601 } },
          sections: event.sections.any? ? event.sections.map(&:slug) : self.class.section_slugs
        )
      end
    end

    private
      def matches
        pattern = KEYWORDS.map { "title LIKE ?" }.join(" OR ")
        user.events.where(starts_at: Time.current..WINDOW.from_now)
          .where(pattern, *KEYWORDS.map { |keyword| "%#{keyword}%" })
      end
  end
end
