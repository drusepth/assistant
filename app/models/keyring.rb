# Per-user vault crypto state (D-vault-crypto) — named Keyring because
# "vault" already means the sidebar's Documents/Photos/Passwords group. The
# vault key exists only wrapped: under a KEK derived from the login password,
# and (once the recovery kit is generated) under a KEK derived from the
# recovery code. The RSA private key rides under the vault key; the public
# key is plaintext by design — it's what item keys get wrapped to.
class Keyring < ApplicationRecord
  VAULT_KEY_AAD = "keyring:v1:vault-key".freeze
  RECOVERY_AAD = "keyring:v1:recovery".freeze
  PRIVATE_KEY_AAD = "keyring:v1:private-key".freeze

  belongs_to :user

  # Runs at a password-bearing moment only (sign-in, setup, join, unlock).
  def self.initialize_for(user, password)
    vault_key = Vault::Crypto.random_key
    keypair = Vault::Crypto.generate_keypair
    salt = Vault::Crypto.random_salt
    kek = Vault::Crypto.derive_kek(password, salt: salt, iterations: Vault::Crypto.kdf_iterations)

    create!(
      user: user,
      key_salt: salt,
      kdf_iterations: Vault::Crypto.kdf_iterations,
      wrapped_key: Vault::Crypto.encrypt(kek, vault_key, aad: VAULT_KEY_AAD),
      public_key: keypair.public_key.to_pem,
      wrapped_private_key: Vault::Crypto.encrypt(vault_key, keypair.to_pem, aad: PRIVATE_KEY_AAD)
    )
  end

  # The unwrapped vault key, or nil — a wrong password is a routine outcome
  # (the unlock banner), not an exception.
  def unlock(password)
    kek = Vault::Crypto.derive_kek(password, salt: key_salt, iterations: kdf_iterations)
    Vault::Crypto.decrypt(kek, wrapped_key, aad: VAULT_KEY_AAD)
  rescue Vault::Crypto::Error
    nil
  end

  def private_key(vault_key)
    OpenSSL::PKey::RSA.new(Vault::Crypto.decrypt(vault_key, wrapped_private_key, aad: PRIVATE_KEY_AAD))
  end

  # Password change: same vault key, new wrap. Nothing else moves.
  def rewrap!(vault_key, new_password)
    salt = Vault::Crypto.random_salt
    kek = Vault::Crypto.derive_kek(new_password, salt: salt, iterations: Vault::Crypto.kdf_iterations)
    update!(key_salt: salt, kdf_iterations: Vault::Crypto.kdf_iterations,
      wrapped_key: Vault::Crypto.encrypt(kek, vault_key, aad: VAULT_KEY_AAD))
  end

  # Generates (or regenerates) the recovery wrap and returns the code — the
  # only time it exists in plaintext. Callable whenever the vault is
  # unlocked; the kit view is the once-only display.
  def generate_recovery!(vault_key)
    code = Vault::Crypto.generate_recovery_code
    salt = Vault::Crypto.random_salt
    kek = Vault::Crypto.derive_kek(Vault::Crypto.normalize_recovery_code(code), salt: salt,
      iterations: Vault::Crypto.kdf_iterations)
    update!(recovery_salt: salt, recovery_confirmed_at: nil, recovery_verified_at: nil,
      recovery_wrapped_key: Vault::Crypto.encrypt(kek, vault_key, aad: RECOVERY_AAD))
    code
  end

  # Proof rather than a promise: the code was pasted back and it opened the
  # vault. `recovery_confirmed_at` only ever meant "someone clicked I saved
  # it", which is enough for passwords and not for a diary — a mistyped kit
  # there costs the whole journal, and nobody else holds a key to it.
  def verify_recovery(code)
    return false if unlock_with_recovery(code).nil?

    update!(recovery_verified_at: Time.current, recovery_confirmed_at: recovery_confirmed_at || Time.current)
    true
  end

  def recovery_verified? = recovery_verified_at.present?

  def unlock_with_recovery(code)
    return nil if recovery_wrapped_key.blank?

    kek = Vault::Crypto.derive_kek(Vault::Crypto.normalize_recovery_code(code), salt: recovery_salt,
      iterations: kdf_iterations)
    Vault::Crypto.decrypt(kek, recovery_wrapped_key, aad: RECOVERY_AAD)
  rescue Vault::Crypto::Error
    nil
  end

  def recovery_pending? = recovery_wrapped_key.blank? || recovery_confirmed_at.nil?

  # The knowing-loss path (password reset without the recovery code): fresh
  # keys so the vault works going forward; the user's own key rows are
  # cryptographically dead and deleted, which is what marks their secrets
  # "lost" — key rows held by grantees survive, so a re-share can restore a
  # shared secret. Emergency escrow rows in both directions die with the keys
  # they were wrapped to. Every sealed container is asked to mark its own
  # loss (D-vault-sealed) rather than being named here: a container this
  # method forgot would leave live wrapped keys behind a vault the user was
  # told is dead.
  def reset!(new_password)
    vault_key = Vault::Crypto.random_key
    keypair = Vault::Crypto.generate_keypair
    salt = Vault::Crypto.random_salt
    kek = Vault::Crypto.derive_kek(new_password, salt: salt, iterations: Vault::Crypto.kdf_iterations)

    transaction do
      update!(
        key_salt: salt,
        kdf_iterations: Vault::Crypto.kdf_iterations,
        wrapped_key: Vault::Crypto.encrypt(kek, vault_key, aad: VAULT_KEY_AAD),
        public_key: keypair.public_key.to_pem,
        wrapped_private_key: Vault::Crypto.encrypt(vault_key, keypair.to_pem, aad: PRIVATE_KEY_AAD),
        recovery_salt: nil, recovery_wrapped_key: nil, recovery_confirmed_at: nil,
        recovery_verified_at: nil, reset_at: Time.current
      )
      VaultSealed::CONTAINERS.each { |container| container.constantize.mark_lost_on_reset!(user) }
      EmergencyContact.where(user: user).or(EmergencyContact.where(contact_user: user)).destroy_all
    end
  end
end
