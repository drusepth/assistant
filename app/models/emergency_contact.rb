# Emergency access (PASSWORDS_PLAN §7): the owner's vault key, escrowed to a
# chosen household member's public key with a waiting period. The wait is
# app-enforced policy, not cryptography — the setup copy says so. Requesting
# starts the clock; the owner can deny with one click (clears the request);
# an undenied request past its wait releases read access, prominently logged.
class EmergencyContact < ApplicationRecord
  WRAP_AAD = "emergency:v1:vault-key".freeze

  belongs_to :user
  belongs_to :contact_user, class_name: "User"

  validates :contact_user_id, uniqueness: { scope: :user_id }
  validates :wait_days, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 90 }
  validate :contact_is_not_owner
  validate :users_share_a_household

  scope :for_contact, ->(user) { where(contact_user: user) }

  def self.escrow!(owner:, contact:, vault_key:, wait_days:)
    create!(user: owner, contact_user: contact, wait_days: wait_days,
      wrapped_vault_key: Vault::Crypto.rsa_wrap(contact.keyring.public_key, vault_key))
  end

  def requested? = requested_at.present?
  def wait_elapsed? = requested? && requested_at <= wait_days.days.ago
  def releasable? = wait_elapsed?

  # The owner's vault key, unwrapped with the contact's private key. Only
  # meaningful once the wait has elapsed — callers check releasable?.
  def owner_vault_key(contact_vault_key)
    Vault::Crypto.rsa_unwrap(contact_user.keyring.private_key(contact_vault_key), wrapped_vault_key)
  rescue Vault::Crypto::Error
    nil
  end

  private
    def contact_is_not_owner
      errors.add(:contact_user, "can't be yourself") if contact_user_id == user_id
    end

    def users_share_a_household
      return if user.nil? || contact_user.nil?

      errors.add(:contact_user, "must be in the same household") if user.household_id != contact_user.household_id
    end
end
