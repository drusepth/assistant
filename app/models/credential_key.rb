# Decryptability, one row per reader (D-vault-crypto): the credential's item
# key wrapped to this user's public key. Visibility is the AccessGrant; this
# row is what actually opens the secret — both are required, and share/revoke
# keep them in lockstep (Vault::Share).
class CredentialKey < ApplicationRecord
  belongs_to :credential
  belongs_to :user

  validates :user_id, uniqueness: { scope: :credential_id }
end
