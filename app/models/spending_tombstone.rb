# A deletion that stays deleted (the EmailTombstone pattern): imports
# skip tombstoned fingerprints, so removing a mis-parsed or private
# transaction can't be undone by re-importing the same statement.
# Purged with the account.
class SpendingTombstone < MirrorRecord
  validates :fingerprint, presence: true, uniqueness: { scope: :spending_account_id }

  def self.covers?(spending_account_id, fingerprint)
    exists?(spending_account_id: spending_account_id, fingerprint: fingerprint)
  end
end
