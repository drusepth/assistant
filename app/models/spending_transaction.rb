# One row of the spending ledger (D-spending-mirror, MONEY.md §2).
# Deliberately NOT a primitive: no Visible, no Sectionable, no grants —
# the mirror pattern's structural privacy, second source. References to
# primary-database rows (user, account, category, statement document)
# are soft ids resolved in Ruby. Amounts are signed cents: negative is
# money out, positive is money in.
class SpendingTransaction < MirrorRecord
  SOURCES = %w[ statement manual email_receipt ].freeze
  CATEGORIZERS = %w[ rule keyword model user ].freeze

  validates :occurred_on, :fingerprint, presence: true
  validates :amount_cents, numericality: { only_integer: true }
  validates :source, inclusion: { in: SOURCES }
  validates :categorized_by, inclusion: { in: CATEGORIZERS }, allow_nil: true

  scope :newest_first, -> { order(occurred_on: :desc, id: :desc) }
  scope :spending, -> { where(transfer: false).where(amount_cents: ...0) }
  scope :income, -> { where(transfer: false).where(amount_cents: 1..) }
  scope :uncategorized, -> { where(budget_category_id: nil, transfer: false) }
  scope :in_month, ->(month) { where(occurred_on: month.beginning_of_month..month.end_of_month) }

  def user = @user ||= User.find_by(id: user_id)

  # Soft cross-database lookups, owner-scoped so a recycled id can never
  # surface someone else's row (the EmailMessage#person precedent).
  def spending_account
    @spending_account ||= SpendingAccount.find_by(id: spending_account_id, user_id: user_id)
  end

  def budget_category
    return nil if budget_category_id.blank?
    @budget_category ||= BudgetCategory.find_by(id: budget_category_id, user_id: user_id)
  end

  def document
    return nil if document_id.blank?
    @document ||= Document.find_by(id: document_id, user_id: user_id)
  end

  def money_out? = amount_cents.negative?
  def money_in? = amount_cents.positive?

  def display_merchant = merchant.presence || descriptor.presence || "(no description)"

  # Recategorization is the one mutation a ledger row supports; the
  # user's word beats every automatic pass (D16's hand-set rule).
  def recategorize!(category)
    update!(budget_category_id: category&.id, categorized_by: category ? "user" : nil)
  end

  # Removal that stays removed: tombstone the fingerprint so re-importing
  # the same statement can't resurrect the row.
  def remove_from_mirror!
    transaction do
      SpendingTombstone.find_or_create_by!(
        spending_account_id: spending_account_id, fingerprint: fingerprint)
      destroy!
    end
  end

  # The dedupe identity when a bank id is absent: same account, same day,
  # same signed amount, same normalized descriptor. A counter suffix is
  # appended by the importer for genuine same-day duplicates.
  def self.fingerprint_for(account_id, occurred_on, amount_cents, descriptor)
    Digest::SHA256.hexdigest(
      [ account_id, occurred_on.to_s, amount_cents, descriptor.to_s.downcase.squish ].join("|")
    ).first(32)
  end
end
