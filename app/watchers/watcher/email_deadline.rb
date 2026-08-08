module Watcher
  # Deadlines that arrived by email (EMAIL_PLAN.md §6): triage labels a
  # stated date, this watcher turns it into a pending suggestion whose
  # accept lands the calendar Event — the agent proposes, the user
  # disposes (D20). Deterministic over the mirror's stored labels; runs on
  # the normal scans AND directly after each triage batch so a fresh
  # deadline doesn't wait a week. Sectionless: mail is a source, not a
  # section (D31).
  class EmailDeadline < Base
    self.section_slugs = []

    LOOKAHEAD = 120 # days a stated deadline may be out and still be worth a card

    def scan
      candidates.each do |message, deadline_on, deadline_title|
        propose(
          fingerprint: "message:#{message.message_id}",
          kind: :heads_up,
          title: "An email mentions a deadline: #{deadline_title || message.subject.presence || "check the message"}",
          body: "From #{message.from_name.presence || message.from_email} — \"#{message.subject.presence || "(no subject)"}\". Want it on your calendar so it can't slip by?",
          action: { "event" => {
            "title" => deadline_title || "Deadline: #{message.subject}".first(120),
            "starts_at" => deadline_on.to_s,
            "all_day" => true
          } }
        )
      end
    end

    private
      def candidates
        EmailMessage.where(user_id: user.id, bulk: false)
          .where.not(triage: nil)
          .where("triaged_at > ?", 30.days.ago)
          .order(triaged_at: :desc).limit(300)
          .filter_map do |message|
            deadline = message.triage&.dig("deadline_on") or next
            date = Date.iso8601(deadline) rescue next
            next unless date.between?(Date.current, Date.current + LOOKAHEAD)
            [ message, date, message.triage["deadline_title"] ]
          end
      end
  end
end
