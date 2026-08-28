module Watcher
  # An interview on the calendar with no prep run behind it (docs/CAREER.md
  # §4): the prep tools exist for exactly this moment, so offer them while
  # there's still time. Pure SQL over events ∪ tool_runs; one nudge per
  # event, ever.
  class InterviewAhead < Base
    self.section_slugs = %w[ career ]

    LEAD_WINDOW = 10.days
    PREP_SLUGS = %w[ interview_prep mock_interview ].freeze

    def scan
      upcoming_interviews.each do |event|
        next if prepped_since?(event)

        propose(
          fingerprint: "event:#{event.id}",
          title: "“#{event.title}” is coming up — want to prep?",
          body: "A prep sheet and a mock round are how the nerves become answers. " \
                "It reads your logged wins, so the stories are yours.",
          action: { "tool" => { "slug" => "interview_prep",
                                "inputs" => { "role" => event.title } },
                    # Past the interview there is nothing left to prep for
                    # (D-suggestion-lifecycle): the day itself retires it.
                    "expires_on" => event.starts_at.to_date.iso8601 }
        )
      end
    end

    # They prepped — through this suggestion or by opening the tool
    # themselves — or the interview came off the calendar.
    def resolved?(suggestion)
      return false unless (id = subject_id(suggestion, "event"))

      event = Event.where(user: user).find_by(id: id)
      return true if event.nil?

      prepped_since?(event)
    end

    private
      def upcoming_interviews
        Event.where(user: user)
          .where(starts_at: Time.current..LEAD_WINDOW.from_now)
          .where("title LIKE ?", "%interview%")
      end

      def prepped_since?(event)
        user.tool_runs.where(tool_slug: PREP_SLUGS)
          .where(created_at: event.created_at..).exists?
      end
  end
end
