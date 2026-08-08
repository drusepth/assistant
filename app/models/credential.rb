# A vault entry (D-passwords-vault): the Album precedent — Visible, never
# Sectionable, and never fed to any model surface. Metadata (name, username,
# url) rides the instance's AR encryption so the list works while locked;
# the secret payload is one AAD-bound AES-256-GCM blob under a per-entry
# item key, wrapped per reader in credential_keys (the owner is just the
# first keyholder). Secrets never appear in a prompt, a log, an AppError
# context, or a background job.
class Credential < ApplicationRecord
  SECRETS_AAD_PREFIX = "credential:v1:".freeze

  # First-party kind registry (D11 style): field sets for capture and reveal.
  # `secret: true` fields live in the encrypted payload; the rest are the
  # metadata tier. Every kind also carries encrypted free-text notes.
  KINDS = {
    "login" => {
      label: "Login",
      secret_fields: %w[ password totp ],
      username_label: "Username", url_label: "Website"
    },
    "wifi" => {
      label: "Wi-Fi network",
      secret_fields: %w[ password ],
      username_label: "Network name (SSID)", url_label: nil
    },
    "card" => {
      label: "Payment card",
      secret_fields: %w[ number expiry code pin ],
      username_label: "Name on card", url_label: nil
    },
    "note" => {
      label: "Sealed note",
      secret_fields: %w[],
      username_label: nil, url_label: nil
    }
  }.freeze

  include Visible

  encrypts :name, :username, :url

  has_many :credential_keys, dependent: :destroy

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS.keys }

  def kind_settings = KINDS.fetch(kind) { KINDS.fetch("login") }
  def secret_field_names = kind_settings[:secret_fields] + [ "notes" ]

  def secrets_aad = SECRETS_AAD_PREFIX + kind

  # Fresh entry: new item key, wrapped to the owner alone.
  def write_secrets!(payload)
    rotate_secrets!(payload, holders: [ user ])
  end

  # Owner edit: keep the item key (grantee wraps stay valid), re-encrypt the
  # merged payload.
  def update_secrets!(payload, item_key)
    store_payload(payload, item_key)
    save!
  end

  # Rotation: fresh item key, re-wrapped for the given holders — the unshare
  # and re-enter paths. Holders without keyrings are skipped (they can't
  # decrypt anything anyway).
  def rotate_secrets!(payload, holders:)
    item_key = Vault::Crypto.random_key
    store_payload(payload, item_key)

    transaction do
      save!
      credential_keys.destroy_all
      holders.uniq.each do |holder|
        next if holder.keyring.nil?

        credential_keys.create!(user: holder,
          wrapped_item_key: Vault::Crypto.rsa_wrap(holder.keyring.public_key, item_key))
      end
    end
  end

  # The one decrypt path, owner and grantee alike (D-vault-crypto).
  def unwrap_item_key(viewer, vault_key)
    row = credential_keys.find_by(user: viewer) or return nil
    Vault::Crypto.rsa_unwrap(viewer.keyring.private_key(vault_key), row.wrapped_item_key)
  rescue Vault::Crypto::Error
    nil
  end

  def read_secrets(viewer, vault_key)
    item_key = unwrap_item_key(viewer, vault_key) or return nil
    read_secrets_with_item_key(item_key)
  end

  def read_secrets_with_item_key(item_key)
    return {} if secrets_ciphertext.blank?

    JSON.parse(Vault::Crypto.decrypt(item_key, secrets_ciphertext, aad: secrets_aad)).except("v")
  rescue Vault::Crypto::Error, JSON::ParserError
    nil
  end

  # The owner's own key row is what marks a secret readable; a password
  # reset without the recovery code deletes it (Keyring#reset!), which is
  # how an entry shows as lost.
  def secret_lost_for?(viewer) = credential_keys.where(user: viewer).none?

  def shared_with = credential_keys.where.not(user_id: user_id).includes(:user).map(&:user)

  private
    def store_payload(payload, item_key)
      payload = payload.compact_blank
      self.totp_present = payload["totp"].present?
      self.secrets_ciphertext =
        Vault::Crypto.encrypt(item_key, payload.merge("v" => 1).to_json, aad: secrets_aad)
      self.secret_changed_at = Time.current
    end
end
