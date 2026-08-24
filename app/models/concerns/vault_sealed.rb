# The item-key envelope, shared by every vault container (D-vault-sealed).
#
# One decrypt path for everyone: *my password → my vault key → my private key
# → the item key wrapped for me → the payload.* Each record gets its own
# random item key encrypting a versioned JSON payload with AES-256-GCM under
# an AAD the including model names; the item key is stored wrapped to the
# public key of every user who may read it, so **sharing is another row, not
# another mechanism**.
#
# Extracted from `Credential` when the diary became the second container.
# Containers differ in three places and nowhere else: the payload column, the
# AAD, and what else a write touches (`after_sealing`). A container whose
# owner reads through something other than a key row — the diary, whose owner
# wrap rides the record itself under the diary key — overrides
# `unwrap_item_key` / `store_item_key_for` / `secret_lost_for?` and inherits
# everything else.
module VaultSealed
  extend ActiveSupport::Concern

  # The registry `Keyring#reset!` walks. Deliberately an explicit list rather
  # than a self-populating one: a container that registers itself only once
  # its class is loaded would be silently skipped by a reset in a
  # not-yet-warm process, leaving live wrapped keys behind a vault the user
  # was told is dead. A hub file everyone appends to conflicts trivially;
  # a security hole that opens only in development does not.
  # `VaultSealedTest` fails if a model includes this concern without joining.
  CONTAINERS = %w[ Credential ].freeze

  included do
    class_attribute :sealed_payload_column, :sealed_keys_name, :sealed_aad_prefix, instance_writer: false
  end

  class_methods do
    # The three per-container facts.
    def seals(payload:, keys:, aad:)
      self.sealed_payload_column = payload.to_s
      self.sealed_keys_name = keys.to_s
      self.sealed_aad_prefix = aad.to_s
    end

    def sealed_key_reflection = reflect_on_association(sealed_keys_name)
    def sealed_key_class = sealed_key_reflection.klass
    def sealed_key_foreign_key = sealed_key_reflection.foreign_key

    # A password reset without the recovery code kills this user's private
    # key, so every wrap addressed to them is already cryptographically
    # dead. Deleting the rows *is* the loss — no per-record flag can drift
    # out of sync with the crypto. Rows other users hold survive, which is
    # what makes a re-share able to restore a shared secret.
    def mark_lost_on_reset!(user)
      user.public_send(sealed_keys_name).destroy_all
    end
  end

  # Fresh record: new item key, wrapped to the owner alone.
  def write_secrets!(payload)
    rotate_secrets!(payload, holders: [ user ])
  end

  # Owner edit: keep the item key (grantee wraps stay valid), re-encrypt the
  # merged payload.
  def update_secrets!(payload, item_key)
    store_sealed_payload(payload, item_key)
    save!
  end

  # Rotation: fresh item key, re-wrapped for the given holders — the unshare
  # and re-enter paths. Holders without keyrings are skipped (they can't
  # decrypt anything anyway).
  def rotate_secrets!(payload, holders:)
    item_key = Vault::Crypto.random_key
    store_sealed_payload(payload, item_key)

    transaction do
      save!
      sealed_keys.destroy_all
      holders.uniq.each { |holder| wrap_item_key_for!(holder, item_key) }
    end
  end

  def unwrap_item_key(viewer, vault_key)
    row = sealed_keys.find_by(user: viewer) or return nil
    Vault::Crypto.rsa_unwrap(viewer.keyring.private_key(vault_key), row.wrapped_item_key)
  rescue Vault::Crypto::Error
    nil
  end

  def read_secrets(viewer, vault_key)
    item_key = unwrap_item_key(viewer, vault_key) or return nil
    read_secrets_with_item_key(item_key)
  end

  def read_secrets_with_item_key(item_key)
    blob = self[sealed_payload_column]
    return {} if blob.blank?

    JSON.parse(Vault::Crypto.decrypt(item_key, blob, aad: sealed_aad)).except("v")
  rescue Vault::Crypto::Error, JSON::ParserError
    nil
  end

  # The viewer's own key row is what marks a payload readable; a password
  # reset without the recovery code deletes it (Keyring#reset!), which is
  # how a record shows as lost.
  def secret_lost_for?(viewer) = sealed_keys.where(user: viewer).none?

  def shared_with = sealed_keys.where.not(user_id: user_id).includes(:user).map(&:user)

  def sealed_keys = public_send(sealed_keys_name)

  # Overridden where the AAD carries more than the prefix (a Credential
  # binds its kind, which is what makes kind immutable after creation).
  def sealed_aad = sealed_aad_prefix

  # One reader's decryptability. A holder with no keyring is skipped rather
  # than raised on — they could not decrypt anything anyway, and asking them
  # to sign in once is the UI's job, not this method's.
  def wrap_item_key_for!(holder, item_key)
    return if holder.keyring.nil?

    sealed_keys.create!(user: holder,
      wrapped_item_key: Vault::Crypto.rsa_wrap(holder.keyring.public_key, item_key))
  end

  private
    def store_sealed_payload(payload, item_key)
      payload = payload.compact_blank
      self[sealed_payload_column] =
        Vault::Crypto.encrypt(item_key, payload.merge("v" => 1).to_json, aad: sealed_aad)
      after_sealing(payload)
    end

    # Hook: whatever else a write touches on this container.
    def after_sealing(payload)
    end
end
