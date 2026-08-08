# The manual floor of the import ladder (MONEY.md §2.1): "14.50 lunch"
# logs money out today, "+500 paycheck" money in — two things typed, D16
# discipline. Rows land on the user's Cash account (created on first
# use) and run through the same deterministic categorization as imports.
class Spending::QuickLog
  PATTERN = /\A\s*([+-])?\s*\$?(\d+(?:[.,]\d{1,2})?)\s+(.{2,}?)\s*\z/

  def self.call(user:, text:)
    match = PATTERN.match(text.to_s) or return nil

    sign, amount, descriptor = match.captures
    cents = Spending::StatementImport.parse_cents(amount) or return nil
    cents = -cents unless sign == "+"

    account = cash_account(user)
    row = SpendingTransaction.create!(
      user_id: user.id,
      spending_account_id: account.id,
      occurred_on: Date.current,
      amount_cents: cents,
      descriptor: descriptor.squish,
      merchant: Spending::Normalize.merchant(descriptor),
      fingerprint: "manual-#{SecureRandom.hex(10)}",
      source: "manual")

    Spending::Categorize.new(user: user).apply_deterministic
    row
  end

  def self.cash_account(user)
    user.spending_accounts.find_by(kind: "cash") ||
      user.spending_accounts.create!(name: "Cash", kind: "cash")
  end
end
