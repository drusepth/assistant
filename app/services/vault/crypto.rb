module Vault
  # The one file that touches OpenSSL (D-vault-crypto). Everything the vault
  # encrypts flows through here: the PBKDF2 KEKs, AAD-bound AES-256-GCM, the
  # RSA-OAEP key wraps, and the RFC 6238 TOTP math. Ciphertexts carry a
  # version byte so algorithms can rotate; KDF params live on each keyring so
  # a future argon2id upgrade is a data migration, not a redesign.
  module Crypto
    class Error < StandardError; end

    VERSION = "\x01".b.freeze
    KEY_BYTES = 32
    IV_BYTES = 12
    TAG_BYTES = 16

    # Overridable so the test suite doesn't pay 600k PBKDF2 rounds and a
    # 3072-bit keygen per keyring. Real KDF cost is recorded per-keyring at
    # creation, so lowering these never weakens an existing wrap.
    mattr_accessor :kdf_iterations, default: 600_000
    mattr_accessor :rsa_bits, default: 3072

    # Recovery codes avoid lookalike characters; input is normalized, so
    # dashes/spaces/case never matter.
    RECOVERY_ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789".freeze

    module_function

    def random_key = SecureRandom.random_bytes(KEY_BYTES)
    def random_salt = SecureRandom.hex(16)

    def derive_kek(password, salt:, iterations:)
      OpenSSL::KDF.pbkdf2_hmac(password.to_s, salt: salt, iterations: iterations,
        length: KEY_BYTES, hash: "SHA256")
    end

    # AES-256-GCM with additional authenticated data: a ciphertext moved to a
    # different row, field, or use fails its tag instead of decrypting.
    def encrypt(key, plaintext, aad:)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      iv = cipher.random_iv
      cipher.auth_data = aad
      ciphertext = cipher.update(plaintext) + cipher.final
      VERSION + iv + cipher.auth_tag + ciphertext
    end

    def decrypt(key, blob, aad:)
      blob = blob.to_s.b
      raise Error, "unknown ciphertext version" unless blob.byteslice(0) == VERSION

      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv = blob.byteslice(1, IV_BYTES)
      cipher.auth_tag = blob.byteslice(1 + IV_BYTES, TAG_BYTES)
      cipher.auth_data = aad
      cipher.update(blob.byteslice((1 + IV_BYTES + TAG_BYTES)..) || "") + cipher.final
    rescue OpenSSL::Cipher::CipherError, ArgumentError
      raise Error, "decryption failed"
    end

    def generate_keypair = OpenSSL::PKey::RSA.new(rsa_bits)

    def rsa_wrap(public_key_pem, key)
      OpenSSL::PKey::RSA.new(public_key_pem).encrypt(key, oaep_options)
    rescue OpenSSL::PKey::PKeyError
      raise Error, "key wrap failed"
    end

    def rsa_unwrap(private_key, wrapped)
      private_key.decrypt(wrapped.to_s.b, oaep_options)
    rescue OpenSSL::PKey::PKeyError
      raise Error, "key unwrap failed"
    end

    def oaep_options
      { rsa_padding_mode: "oaep", rsa_oaep_md: "sha256", rsa_mgf1_md: "sha256" }
    end

    def generate_recovery_code
      Array.new(4) { Array.new(6) { RECOVERY_ALPHABET[SecureRandom.random_number(RECOVERY_ALPHABET.length)] }.join }.join("-")
    end

    def normalize_recovery_code(code)
      code.to_s.upcase.gsub(/[^#{RECOVERY_ALPHABET}]/o, "")
    end

    # RFC 6238: 30-second step, six digits, HMAC-SHA1 — what every enrollment
    # QR out there actually uses.
    def totp_code(secret, at: Time.current)
      counter = at.to_i / 30
      hmac = OpenSSL::HMAC.digest("SHA1", base32_decode(secret), [ counter ].pack("Q>"))
      offset = hmac.bytes.last & 0x0f
      format("%06d", (hmac.byteslice(offset, 4).unpack1("N") & 0x7fffffff) % 1_000_000)
    end

    def totp_seconds_remaining(at: Time.current) = 30 - (at.to_i % 30)

    # Accepts a bare base32 seed or a pasted otpauth:// URI.
    def normalize_totp_secret(input)
      input = input.to_s.strip
      input = Rack::Utils.parse_query(URI(input).query)["secret"].to_s if input.start_with?("otpauth://")
      secret = input.delete(" -").upcase
      raise Error, "invalid TOTP secret" if secret.blank?

      base32_decode(secret) # raises on non-base32 input
      secret
    rescue URI::InvalidURIError
      raise Error, "invalid TOTP secret"
    end

    def base32_decode(str)
      alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
      bits = str.to_s.upcase.delete("= ").each_char.map do |char|
        index = alphabet.index(char) or raise Error, "invalid TOTP secret"
        index.to_s(2).rjust(5, "0")
      end.join
      [ bits.slice(0, bits.length - bits.length % 8) ].pack("B*")
    end
  end
end
