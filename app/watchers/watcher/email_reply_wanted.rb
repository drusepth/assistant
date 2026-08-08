module Watcher
  # The user-armed boomerang (EMAIL_PLAN.md §7): "remind me if no reply
  # by ___". Zero AI, zero false positives — the user declared the
  # expectation on the message page, this watcher only keeps the promise.
  # Sectionless (mail is a source, not a section — D-email-monitoring); suggestions file
  # under People; the trust anchor for the two inferred boomerangs.
  class EmailReplyWanted < Base
    self.section_slugs = []

    def scan
      due_messages.each do |message|
        next if message.replied_to?

        counterparty = message.person&.name || message.counterparty_email || "them"
        propose(
          fingerprint: "message:#{message.message_id}/#{message.reply_wanted_by}",
          title: "Still no reply from #{counterparty} about “#{message.subject.presence || "(no subject)"}”",
          body: "You asked to be nudged if this went unanswered by #{message.reply_wanted_by.strftime("%B %-d")}. It has.",
          action: { "tool" => { "slug" => "email_follow_up", "inputs" => { "email_id" => message.id.to_s } } },
          sections: %w[ people ]
        )
      end
    end

    private
      def due_messages
        EmailMessage.where(user_id: user.id, direction: "outbound")
          .where(reply_wanted_by: ..Date.current)
          .order(reply_wanted_by: :desc).limit(20)
      end
  end
end
