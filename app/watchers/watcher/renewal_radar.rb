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
          action: { "task" => { "title" => follow_up_title(event), "due_on" => act_by.iso8601 },
                    # Lead time is the whole point, so the date it was about
                    # is the date the heads-up stops being one.
                    "expires_on" => event.starts_at.to_date.iso8601 },
          sections: event.sections.any? ? event.sections.map(&:slug) : self.class.section_slugs
        )
      end
    end

    # The event is gone, or the follow-up work exists. The title match is
    # against a title this watcher itself composes — the pet-food-shelf
    # convention, so the nudge and the task it proposes can't talk over each
    # other — not an attempt to recognize work by reading it.
    def resolved?(suggestion)
      return false unless (id = subject_id(suggestion, "event"))

      event = user.events.find_by(id: id)
      return true if event.nil?

      user.tasks.open.exists?(title: follow_up_title(event))
    end

    private
      def follow_up_title(event) = "Sort out: #{event.title}"

      def matches
        pattern = KEYWORDS.map { "title LIKE ?" }.join(" OR ")
        user.events.where(starts_at: Time.current..WINDOW.from_now)
          .where(pattern, *KEYWORDS.map { |keyword| "%#{keyword}%" })
      end
  end
end
