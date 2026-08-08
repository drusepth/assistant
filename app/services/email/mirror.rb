# Mirror lifecycle (EMAIL_PLAN.md §3): unlinking a mailbox purges its
# cache in one pass — messages, folders, tombstones, provenance, FTS
# rows. Promoted primitives survive by construction: promotion copies
# content out and never links back into the cache as a dependency (D32).
class Email::Mirror
  def self.purge(account)
    message_ids = EmailMessage.where(linked_account_id: account.id).pluck(:id)

    Email::Search.remove_ids(message_ids)
    EmailMessageItem.where(email_message_id: message_ids).delete_all
    EmailMessage.where(linked_account_id: account.id).delete_all
    EmailFolder.where(linked_account_id: account.id).delete_all
    EmailTombstone.where(linked_account_id: account.id).delete_all
  end
end
