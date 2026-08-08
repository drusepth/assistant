# Where a transaction came from: a checking account, a credit card, or
# the cash in your pocket. Owned config in the primary database (the
# linked_accounts precedent — config in primary, firehose in mirror);
# the rows it explains live in the spending mirror (D-spending-mirror).
# Full account numbers are never stored — last4 is display only.
class SpendingAccount < ApplicationRecord
  KINDS = %w[ checking credit cash ].freeze

  belongs_to :user

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }

  before_validation { self.last4 = last4.to_s.gsub(/\D/, "").last(4).presence }

  # Unlinking an account purges its slice of the mirror — same lifecycle
  # as unlinking a mailbox (Email::Mirror).
  before_destroy { Spending::Mirror.purge(self) }

  def transactions
    SpendingTransaction.where(spending_account_id: id)
  end

  def kind_label
    { "checking" => "Bank account", "credit" => "Credit card", "cash" => "Cash" }[kind]
  end

  def display_name
    last4.present? ? "#{name} ····#{last4}" : name
  end
end
