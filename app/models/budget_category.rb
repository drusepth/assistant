# One envelope in the budget (D-budget-envelopes, MONEY.md §3): a name,
# a group, and an optional monthly target. Categories do double duty as
# the ledger's categorization target — one list, two jobs, no parallel
# taxonomies. Per-user and private: not a primitive, no Visible, no
# grants path (joint budgets are Q-household-budget, honestly deferred).
class BudgetCategory < ApplicationRecord
  GROUPS = %w[ income needs wants savings_debt ].freeze
  GROUP_LABELS = {
    "income" => "Income", "needs" => "Needs",
    "wants" => "Wants", "savings_debt" => "Savings & debt"
  }.freeze
  TARGET_SETTERS = %w[ user tool ].freeze

  belongs_to :user
  has_many :spending_rules, dependent: :destroy

  validates :name, presence: true,
    uniqueness: { scope: :user_id, case_sensitive: false }
  validates :group, inclusion: { in: GROUPS }
  validates :target_set_by, inclusion: { in: TARGET_SETTERS }, allow_nil: true
  validates :monthly_target_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(Arel.sql("position IS NULL"), :position, :name) }

  def group_label = GROUP_LABELS[group]
  def income? = group == "income"
  def archived? = archived_at.present?

  # The D16 hand-set guard: a target the user typed is never overwritten
  # by a tool's suggest-and-apply pass.
  def target_hand_set? = target_set_by == "user" && monthly_target_cents.present?

  def transactions
    SpendingTransaction.where(user_id: user_id, budget_category_id: id)
  end
end
