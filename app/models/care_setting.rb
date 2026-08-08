# One user's tuning of one care-radar kind (docs/HEALTH.md §3): mute it,
# override its interval, or — for rows whose kind_key isn't in the registry —
# define a custom kind ("Dermatology", every 12 months) that classifies by
# its own label. A missing row means registry defaults; a row matching the
# defaults is harmless.
class CareSetting < ApplicationRecord
  belongs_to :user

  validates :kind_key, presence: true, format: { with: /\A[a-z0-9_]+\z/ },
    uniqueness: { scope: :user_id }
  validates :label, presence: true, if: :custom?
  validates :interval_months,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 120 },
    allow_nil: true

  scope :custom, -> { where.not(kind_key: Health::CareRadar::KINDS.map(&:key)) }

  def custom? = Health::CareRadar::KINDS.none? { |kind| kind.key == kind_key }
end
