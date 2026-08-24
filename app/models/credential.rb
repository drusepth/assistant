# A vault entry (D-passwords-vault): the Album precedent — Visible, never
# Sectionable, and never fed to any model surface. Metadata (name, username,
# url) rides the instance's AR encryption so the list works while locked;
# the secret payload is one AAD-bound AES-256-GCM blob under a per-entry
# item key, wrapped per reader in credential_keys (the owner is just the
# first keyholder) — the `VaultSealed` envelope, shared with the diary
# (D-vault-sealed). Secrets never appear in a prompt, a log, an AppError
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
  include VaultSealed

  seals payload: :secrets_ciphertext, keys: :credential_keys, aad: SECRETS_AAD_PREFIX

  encrypts :name, :username, :url

  has_many :credential_keys, dependent: :destroy
  has_many :vault_events, as: :subject, dependent: :destroy

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS.keys }

  def kind_settings = KINDS.fetch(kind) { KINDS.fetch("login") }
  def secret_field_names = kind_settings[:secret_fields] + [ "notes" ]

  # The kind rides the AAD, which is what makes it immutable after creation:
  # a payload sealed as one kind fails its tag when read as another.
  def sealed_aad = SECRETS_AAD_PREFIX + kind
  alias_method :secrets_aad, :sealed_aad

  private
    def after_sealing(payload)
      self.totp_present = payload["totp"].present?
      self.secret_changed_at = Time.current
    end
end
