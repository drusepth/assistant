# The feedback loop's memory (EMAIL_PLAN.md §6, D-email-monitoring): user-taught,
# deterministic, user-level (spans mailboxes), and consumed BEFORE the
# model — mute means no LLM call ever, vip means an importance floor no
# model verdict can lower. Written by one-click "Not important" / "More
# like this" on digest rows and alerts; listed and removable in Settings
# (D9: visible configuration, never hidden state). Lives in the primary
# database: it's taught configuration, not re-syncable cache.
class EmailSenderRule < ApplicationRecord
  RULES = %w[ vip mute ].freeze
  VIP_IMPORTANCE_FLOOR = 2

  belongs_to :user

  validates :email, presence: true, uniqueness: { scope: :user_id }
  validates :rule, inclusion: { in: RULES }

  before_validation { self.email = email.to_s.downcase.strip }

  scope :muted, -> { where(rule: "mute") }
  scope :vip, -> { where(rule: "vip") }

  def self.for(user)
    where(user: user).pluck(:email, :rule).to_h
  end
end
