module Watcher
  # The inferred boomerang (EMAIL_PLAN.md §7): you emailed someone a week
  # ago, triage judged it a message that expects an answer, and none came.
  # Gated on the expects_reply label — no model, no label, no nudge (the
  # Q8 lesson: wrong follow-up nudges cost trust the way wrong call-your-
  # mom nudges do). Pure SQL over the Sent mirror at scan time.
  class EmailNoReply < Base
    self.section_slugs = []

    WAIT = 7.days
    LIMIT = 3 # live nudges at a time — the stale-task convention

    def scan
      slots = LIMIT - user.suggestions.actionable.where(watcher_slug: self.class.slug).count
      return unless slots.positive?

      candidates.each do |message|
        break unless slots.positive?
        next if message.replied_to?
        next if followed_up?(message)
        next if noreply_recipient?(message)

        counterparty = message.person&.name || message.counterparty_email || "them"
        days = ((Time.current - message.sent_at) / 1.day).floor
        slots -= 1 if propose(
          # Monthly bucket per thread (the goal-stall convention): a
          # dismissal quiets the thread this month; it may fairly return.
          fingerprint: "thread:#{message.thread_key}/#{Date.current.strftime("%Y-%m")}",
          title: "No reply from #{counterparty} about “#{message.subject.presence || "(no subject)"}” in #{days} days",
          body: "You asked them something and the thread went quiet. A short nudge usually lands well — want one drafted?",
          action: { "tool" => { "slug" => "email_follow_up", "inputs" => { "email_id" => message.id.to_s } } },
          sections: %w[ people ]
        )
      end
    end

    private
      def candidates
        EmailMessage.where(user_id: user.id, direction: "outbound", expects_reply: true, bulk: false)
          .where(sent_at: ..WAIT.ago)
          .order(sent_at: :desc).limit(50)
      end

      # The user already sent a later message in this thread — they don't
      # need a nudge to do what they did.
      def followed_up?(message)
        message.thread_messages.outbound.where("sent_at > ?", message.sent_at).exists?
      end

      def noreply_recipient?(message)
        message.counterparty_email.to_s.match?(/\A(no-?reply|do-?not-?reply|notifications?)@/i)
      end
  end
end
