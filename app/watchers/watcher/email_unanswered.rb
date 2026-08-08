module Watcher
  # The inverse boomerang (EMAIL_PLAN.md §7): mail YOU never answered
  # that expected an answer — for many people the bigger pain. Same
  # gating discipline as EmailNoReply: triage's expects_reply label or
  # silence, muted senders never nudge, capped and bucketed.
  class EmailUnanswered < Base
    self.section_slugs = []

    WAIT = 4.days
    LIMIT = 3

    def scan
      slots = LIMIT - user.suggestions.actionable.where(watcher_slug: self.class.slug).count
      return unless slots.positive?

      muted = EmailSenderRule.muted.where(user: user).pluck(:email)

      candidates.each do |message|
        break unless slots.positive?
        next if muted.include?(message.from_email.to_s)
        next if answered?(message)

        sender = message.person&.name || message.from_name.presence || message.from_email
        slots -= 1 if propose(
          fingerprint: "thread:#{message.thread_key}/#{Date.current.strftime("%Y-%m")}",
          title: "#{sender} is waiting on a reply about “#{message.subject.presence || "(no subject)"}”",
          body: "They asked you something on #{message.sent_at.strftime("%B %-d")} and haven't heard back. Want a reply drafted?",
          action: { "tool" => { "slug" => "email_follow_up", "inputs" => { "email_id" => message.id.to_s } } },
          sections: %w[ people ]
        )
      end
    end

    private
      def candidates
        EmailMessage.where(user_id: user.id, direction: "inbound", expects_reply: true, bulk: false)
          .where(sent_at: ..WAIT.ago)
          .where("triage IS NULL OR json_extract(triage, '$.category') != 'noise'")
          .order(sent_at: :desc).limit(50)
      end

      def answered?(message)
        message.thread_messages.outbound.where("sent_at > ?", message.sent_at).exists?
      end
  end
end
