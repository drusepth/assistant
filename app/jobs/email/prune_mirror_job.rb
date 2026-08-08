# Nightly retention for the email mirror (EMAIL_PLAN.md §4): the mirror
# is a window, not an archive — the mailbox itself remains the record.
# Rows older than the link's window are deleted UNLESS something still
# depends on them: promoted (provenance rows), reply-armed (user
# boomerang), or — from E3 on — sender-ruled. Q14's "mirror everything"
# is window 0.
class Email::PruneMirrorJob < ApplicationJob
  queue_as :default

  def self.prune_all
    LinkedAccount.where(provider: "email").find_each { |account| perform_later(account) }
  end

  def perform(account)
    days = account.setting(:mirror_window_days)
    days = Email::ImapSync::WINDOW_DAYS_DEFAULT if days.nil?
    return if days.to_i <= 0 # "mirror everything"

    cutoff = days.to_i.days.ago
    doomed = EmailMessage.where(linked_account_id: account.id)
      .where(sent_at: ...cutoff)
      .where(reply_wanted_by: nil)
      .where.not(id: EmailMessageItem.select(:email_message_id))
    doomed = doomed.where.not(from_email: kept_senders(account)) if kept_senders(account).any?

    ids = doomed.pluck(:id)
    return if ids.empty?

    Email::Search.remove_ids(ids)
    EmailMessage.where(id: ids).delete_all
  end

  private
    # Sender rules land in E3; until the table exists this keeps nothing
    # extra. Defined here so the prune's keep-exceptions live in one place.
    def kept_senders(account)
      @kept_senders ||= if defined?(EmailSenderRule)
        EmailSenderRule.where(user_id: account.user_id).pluck(:email)
      else
        []
      end
    end
end
