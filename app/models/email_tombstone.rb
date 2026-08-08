# A deletion that stays deleted (EMAIL_PLAN.md §3): sync skips tombstoned
# message_ids, so "remove from mirror" can't be undone by the next poll.
# Purged with the link.
class EmailTombstone < MirrorRecord
  validates :message_id, presence: true, uniqueness: { scope: :linked_account_id }

  def self.covers?(linked_account_id, message_id)
    exists?(linked_account_id: linked_account_id, message_id: message_id)
  end
end
