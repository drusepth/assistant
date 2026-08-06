# A link-based invitation to join a household. Deliberately not email-based:
# self-hosted instances rarely have SMTP configured, so the admin copies a
# signed join link and sends it however the household already communicates.
class Invitation < ApplicationRecord
  belongs_to :household
  belongs_to :inviter, class_name: "User"

  validates :name, presence: true

  scope :pending, -> { where(accepted_at: nil) }

  # Token dies when the invitation is accepted (payload changes) or destroyed,
  # and expires on its own after a week.
  generates_token_for :acceptance, expires_in: 7.days do
    accepted_at
  end

  def accepted? = accepted_at.present?

  def join_token
    generate_token_for(:acceptance)
  end
end
