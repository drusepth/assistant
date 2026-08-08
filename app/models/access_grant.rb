# A user-created, always-visible sharing rule (D9). Two granularities:
# subject = a primitive the grantor owns (share this one item), or
# subject = a Section (share all my items tagged with this section).
class AccessGrant < ApplicationRecord
  ITEM_TYPES = %w[ Event Task Document Person Goal Note Photo Album Credential ].freeze

  belongs_to :grantor, class_name: "User"
  belongs_to :grantee, class_name: "User"
  belongs_to :subject, polymorphic: true

  validates :subject_type, inclusion: { in: ITEM_TYPES + [ "Section" ] }
  validates :grantee_id, uniqueness: { scope: [ :grantor_id, :subject_type, :subject_id ] }
  validate :grantee_is_not_grantor
  validate :users_share_a_household
  validate :grantor_owns_subject

  # Visibility and decryptability stay in lockstep (D-vault-crypto): however
  # a credential grant dies — Vault::Share's unshare, a cascade, the console —
  # the grantee's wrapped item key dies with it. (Item-key rotation is the
  # unshare route's extra step; it needs the owner's unlocked vault.)
  after_destroy :destroy_credential_key

  private
    def destroy_credential_key
      return unless subject_type == "Credential"

      CredentialKey.where(credential_id: subject_id, user_id: grantee_id).destroy_all
    end

    def grantee_is_not_grantor
      errors.add(:grantee, "can't be the grantor") if grantee_id == grantor_id
    end

    def users_share_a_household
      return if grantor.nil? || grantee.nil?
      errors.add(:grantee, "must be in the same household") if grantor.household_id != grantee.household_id
    end

    def grantor_owns_subject
      return if subject.nil? || subject_type == "Section"
      errors.add(:subject, "must belong to the grantor") if subject.user_id != grantor_id
    end
end
