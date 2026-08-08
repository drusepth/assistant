# Paying a credit card from checking is not spending, and counting it
# twice is the classic budget-app trust-killer (MONEY.md §2.3). This
# pairs opposite-signed, same-amount rows across a user's own accounts
# within a few days and flags both sides `transfer`. Deterministic and
# idempotent — re-run after every import — and it never touches a row
# whose transfer flag a human set (transfer_set_by "user" is final).
class Spending::Transfers
  WINDOW_DAYS = 4

  def self.pair(user)
    account_ids = SpendingAccount.where(user_id: user.id).pluck(:id)
    return if account_ids.size < 2

    rows = SpendingTransaction
      .where(user_id: user.id, transfer: false)
      .where(transfer_set_by: nil)
      .where.not(amount_cents: 0)
      .order(:occurred_on, :id)
      .to_a
    by_amount = rows.group_by(&:amount_cents)
    paired = Set.new

    rows.each do |row|
      next if row.amount_cents.positive? || paired.include?(row.id)

      match = Array(by_amount[-row.amount_cents]).find do |other|
        !paired.include?(other.id) &&
          other.spending_account_id != row.spending_account_id &&
          (other.occurred_on - row.occurred_on).abs <= WINDOW_DAYS
      end
      next unless match

      paired << row.id << match.id
      SpendingTransaction.where(id: [ row.id, match.id ])
        .update_all(transfer: true, transfer_set_by: "auto", updated_at: Time.current)
    end
  end
end
