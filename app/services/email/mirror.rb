# Mirror lifecycle (EMAIL_PLAN.md §3): unlinking a mailbox purges its
# cache in one pass — messages, folders, tombstones, provenance, FTS
# rows. Promoted primitives survive by construction: promotion copies
# content out and never links back into the cache as a dependency (D-mirror-database).
class Email::Mirror
  def self.purge(account)
    purge_links([ account.id ])
  end

  # No foreign key can reach across the two databases (D-mirror-database),
  # so a link row disappearing by any path other than `destroy` — a
  # `delete_all`, a wiped household (D-household-reset) — would strand its
  # mail here. This sweeps whatever the callbacks didn't: mirror rows whose
  # linked account no longer exists in the primary database.
  def self.purge_orphans
    live = LinkedAccount.where(provider: "email").pluck(:id)
    stale = EmailFolder.where.not(linked_account_id: live).distinct.pluck(:linked_account_id) |
            EmailMessage.where.not(linked_account_id: live).distinct.pluck(:linked_account_id) |
            EmailTombstone.where.not(linked_account_id: live).distinct.pluck(:linked_account_id)

    purge_links(stale) if stale.any?
  end

  def self.purge_links(link_ids)
    message_ids = EmailMessage.where(linked_account_id: link_ids).pluck(:id)

    Email::Search.remove_ids(message_ids)
    EmailMessageItem.where(email_message_id: message_ids).delete_all
    EmailMessage.where(linked_account_id: link_ids).delete_all
    EmailFolder.where(linked_account_id: link_ids).delete_all
    EmailTombstone.where(linked_account_id: link_ids).delete_all
  end
end
