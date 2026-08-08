# The unlocked vault key's only home (D-vault-crypto): an encrypted,
# HttpOnly cookie path-scoped to /credentials — so the key rests on the
# client sealed under secret_key_base, transits only on vault requests, and
# nothing at rest server-side can open a vault. The payload is bound to the
# user AND the session (sign-out structurally kills the unlock) and expires
# after UNLOCK_WINDOW.
module VaultSession
  UNLOCK_WINDOW = 12.hours
  COOKIE = :keyring
  COOKIE_PATH = "/credentials".freeze

  # Called at password-bearing moments (sign-in, setup, join, explicit
  # unlock). Also lazily initializes the keyring the first time (§4.2).
  def unlock_vault_for(user, password)
    keyring = user.keyring || Keyring.initialize_for(user, password)
    vault_key = keyring.unlock(password) or return false

    grant_vault_key(user, vault_key)
    true
  rescue Vault::Crypto::Error
    false
  end

  def grant_vault_key(user, vault_key)
    cookies.encrypted[COOKIE] = {
      value: {
        "u" => user.id,
        "s" => Current.session&.id,
        "k" => Base64.strict_encode64(vault_key),
        "t" => Time.current.to_i
      }.to_json,
      path: COOKIE_PATH, httponly: true, same_site: :lax
    }
  end

  def vault_key
    return @vault_key if defined?(@vault_key)

    @vault_key = read_vault_key
  end

  def vault_unlocked? = vault_key.present?

  def lock_vault
    cookies.delete(COOKIE, path: COOKIE_PATH)
    @vault_key = nil
  end

  private
    def read_vault_key
      payload = JSON.parse(cookies.encrypted[COOKIE].to_s)
      return nil unless payload["u"] == Current.user&.id
      return nil unless payload["s"] == Current.session&.id
      return nil if payload["t"].to_i < UNLOCK_WINDOW.ago.to_i

      Base64.strict_decode64(payload["k"])
    rescue JSON::ParserError, ArgumentError
      nil
    end
end
