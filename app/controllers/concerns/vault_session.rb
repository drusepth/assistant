# The unlocked vault key's only home (D-vault-crypto): an encrypted,
# HttpOnly cookie path-scoped to the vault surfaces — so the key rests on the
# client sealed under secret_key_base, transits only on vault requests, and
# nothing at rest server-side can open a vault. The payload is bound to the
# user AND the session (sign-out structurally kills the unlock) and expires
# after UNLOCK_WINDOW.
module VaultSession
  UNLOCK_WINDOW = 12.hours

  # One cookie per sealed surface, each scoped to its own prefix
  # (D-vault-sealed). A second container is a row appended here — never a
  # widening of the scope to "/", which would put the unwrapped vault key on
  # every chat message, upload, and page view in the app and give up the
  # invariant the path scoping exists to hold.
  #
  # The names differ because Rails' cookie jar is keyed by name alone: two
  # `Set-Cookie`s under one name in a single response are one entry in the
  # jar, and the last write silently wins. The paths are disjoint, so exactly
  # one of these ever reaches a given request. `:keyring` keeps its original
  # name so the passwords vault survives the deploy that adds the diary.
  COOKIES = { "/credentials" => :keyring, "/diary" => :keyring_diary }.freeze

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
    payload = {
      "u" => user.id,
      "s" => Current.session&.id,
      "k" => Base64.strict_encode64(vault_key),
      "t" => Time.current.to_i
    }.to_json

    COOKIES.each do |path, name|
      cookies.encrypted[name] = { value: payload, path: path, httponly: true, same_site: :lax }
    end
  end

  def vault_key
    return @vault_key if defined?(@vault_key)

    @vault_key = read_vault_key
  end

  def vault_unlocked? = vault_key.present?

  # Locking one surface locks them all: one keyring, one mental model.
  #
  # Written as an explicit expiry rather than `cookies.delete`, which returns
  # early for any cookie not in the *request* jar — and a lock posted from
  # /credentials never carries the /diary cookie, so a delete would silently
  # leave the other surface unlocked.
  def lock_vault
    COOKIES.each do |path, name|
      cookies[name] = { value: "", path: path, expires: Time.at(0), httponly: true, same_site: :lax }
    end
    @vault_key = nil
  end

  private
    def read_vault_key
      COOKIES.each_value do |name|
        key = decode_vault_key(cookies.encrypted[name])
        return key if key
      end
      nil
    end

    def decode_vault_key(raw)
      payload = JSON.parse(raw.to_s)
      return nil unless payload["u"] == Current.user&.id
      return nil unless payload["s"] == Current.session&.id
      return nil if payload["t"].to_i < UNLOCK_WINDOW.ago.to_i

      Base64.strict_decode64(payload["k"])
    rescue JSON::ParserError, ArgumentError
      nil
    end
end
