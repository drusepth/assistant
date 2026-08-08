# Spending-mirror lifecycle (D-spending-mirror): deleting an account
# purges its slice of the ledger in one pass — transactions and
# tombstones. Same shape as Email::Mirror, including the orphan sweep
# that covers rows stranded by any path other than `destroy` (a
# `delete_all`, a wiped household — D-household-reset).
class Spending::Mirror
  def self.purge(account)
    purge_accounts([ account.id ])
  end

  def self.purge_orphans
    live = SpendingAccount.pluck(:id)
    stale = SpendingTransaction.where.not(spending_account_id: live).distinct.pluck(:spending_account_id) |
            SpendingTombstone.where.not(spending_account_id: live).distinct.pluck(:spending_account_id)

    purge_accounts(stale) if stale.any?
  end

  def self.purge_accounts(account_ids)
    SpendingTransaction.where(spending_account_id: account_ids).delete_all
    SpendingTombstone.where(spending_account_id: account_ids).delete_all
  end
end
