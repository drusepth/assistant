# The vault's audit trail (resolves Q-vault-audit): the high-signal,
# low-volume events only — who a credential was shared with or revoked from,
# and every step of an emergency-access request. Routine reveals are
# deliberately *not* logged: they're the owner's own clicks, they'd bury the
# events that matter, and `last_used_at` already answers "when did I last
# use this". If agents ever touch credentials (W6), their use belongs here.
#
# Nothing in this table is a secret — names and verbs only.
class VaultEvent < ApplicationRecord
  ACTIONS = %w[
    shared unshared
    emergency_added emergency_revoked
    emergency_requested emergency_denied emergency_opened
  ].freeze

  belongs_to :user
  belongs_to :actor, class_name: "User"
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :subject_user, class_name: "User", optional: true

  validates :action, inclusion: { in: ACTIONS }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :vault_wide, -> { where(subject_id: nil) }

  # Each container shows its own history plus the vault-wide events, which
  # belong to the keyring rather than to any one container — an emergency
  # contact opens *the vault*, not a password.
  scope :for_container, ->(type) { where(subject_type: [ nil, type ]) }

  # Recording must never break the thing it observes (the D23 posture).
  # `subject:` takes any sealed container (D-vault-sealed) — a credential,
  # a diary entry — or nothing at all, for the events that belong to the
  # vault itself.
  def self.record(action, user:, actor:, subject: nil, subject_user: nil)
    create!(action: action, user: user, actor: actor, subject: subject, subject_user: subject_user)
  rescue StandardError => error
    AppError.record(error, source: "VaultEvent.record", user: actor)
    nil
  end

  def describe
    who = subject_user&.name
    case action
    when "shared" then "Shared with #{who}"
    when "unshared" then "Sharing revoked from #{who} — entry re-keyed"
    when "emergency_added" then "#{who} added as an emergency contact"
    when "emergency_revoked" then "#{who} removed as an emergency contact"
    when "emergency_requested" then "#{actor.name} requested emergency access"
    when "emergency_denied" then "Emergency access denied for #{who}"
    when "emergency_opened" then "#{actor.name} opened emergency access to your vault"
    end
  end

  # Emergency events are the ones worth a visual shout on the index.
  def alarming? = action.start_with?("emergency_") && action != "emergency_revoked"
end
