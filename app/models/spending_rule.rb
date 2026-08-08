# The categorization feedback loop's memory (D-budget-envelopes) — the
# EmailSenderRule pattern for merchants: user-taught, deterministic, and
# consulted BEFORE keywords or the model. Written almost entirely by
# one-click "always file <merchant> here" while recategorizing; listed
# and removable wherever it's created (D9: visible configuration). Lives
# in the primary database: taught config, not re-syncable cache.
class SpendingRule < ApplicationRecord
  belongs_to :user
  belongs_to :budget_category

  validates :matcher, presence: true, uniqueness: { scope: :user_id }

  before_validation { self.matcher = matcher.to_s.downcase.strip }

  # matcher → budget_category_id, longest matcher first so the most
  # specific rule wins ("amazon fresh" beats "amazon").
  def self.for(user)
    where(user: user).order(Arel.sql("LENGTH(matcher) DESC")).pluck(:matcher, :budget_category_id)
  end
end
