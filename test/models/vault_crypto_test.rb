require "test_helper"

# Known-answer and property tests for the crypto core (PASSWORDS_PLAN W1):
# a refactor that silently changes ciphertext framing, AAD binding, or the
# TOTP math must fail here loudly.
class VaultCryptoTest < ActiveSupport::TestCase
  AAD = "test:v1".freeze

  test "gcm round-trips with matching aad" do
    key = Vault::Crypto.random_key
    blob = Vault::Crypto.encrypt(key, "the secret", aad: AAD)

    assert_equal "the secret", Vault::Crypto.decrypt(key, blob, aad: AAD)
  end

  test "ciphertext starts with the version byte and fails on unknown versions" do
    key = Vault::Crypto.random_key
    blob = Vault::Crypto.encrypt(key, "x", aad: AAD)

    assert_equal "\x01".b, blob.byteslice(0)
    tampered = "\x02".b + blob.byteslice(1..)
    assert_raises(Vault::Crypto::Error) { Vault::Crypto.decrypt(key, tampered, aad: AAD) }
  end

  test "a ciphertext moved to a different aad refuses to decrypt" do
    key = Vault::Crypto.random_key
    blob = Vault::Crypto.encrypt(key, "x", aad: "credential:v1:login")

    assert_raises(Vault::Crypto::Error) { Vault::Crypto.decrypt(key, blob, aad: "credential:v1:card") }
  end

  test "a flipped ciphertext byte fails the tag" do
    key = Vault::Crypto.random_key
    blob = Vault::Crypto.encrypt(key, "payload", aad: AAD)
    flipped = blob.dup
    flipped.setbyte(flipped.bytesize - 1, flipped.getbyte(flipped.bytesize - 1) ^ 1)

    assert_raises(Vault::Crypto::Error) { Vault::Crypto.decrypt(key, flipped, aad: AAD) }
  end

  test "kdf is deterministic per salt and sensitive to it" do
    a = Vault::Crypto.derive_kek("pw", salt: "salt-a", iterations: 1000)

    assert_equal a, Vault::Crypto.derive_kek("pw", salt: "salt-a", iterations: 1000)
    refute_equal a, Vault::Crypto.derive_kek("pw", salt: "salt-b", iterations: 1000)
    refute_equal a, Vault::Crypto.derive_kek("pw2", salt: "salt-a", iterations: 1000)
  end

  test "rsa wrap round-trips a key" do
    keypair = Vault::Crypto.generate_keypair
    item_key = Vault::Crypto.random_key
    wrapped = Vault::Crypto.rsa_wrap(keypair.public_key.to_pem, item_key)

    assert_equal item_key, Vault::Crypto.rsa_unwrap(keypair, wrapped)
    refute_equal item_key, wrapped
  end

  test "rsa unwrap with the wrong private key raises our error" do
    wrapped = Vault::Crypto.rsa_wrap(Vault::Crypto.generate_keypair.public_key.to_pem, Vault::Crypto.random_key)

    assert_raises(Vault::Crypto::Error) { Vault::Crypto.rsa_unwrap(Vault::Crypto.generate_keypair, wrapped) }
  end

  test "totp matches the rfc 6238 sha1 vectors" do
    seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" # ASCII "12345678901234567890"

    assert_equal "287082", Vault::Crypto.totp_code(seed, at: Time.at(59))
    assert_equal "081804", Vault::Crypto.totp_code(seed, at: Time.at(1_111_111_109))
    assert_equal "005924", Vault::Crypto.totp_code(seed, at: Time.at(1_234_567_890))
  end

  test "totp secret normalization takes otpauth uris, spaces, and case" do
    assert_equal "JBSWY3DPEHPK3PXP", Vault::Crypto.normalize_totp_secret("jbsw y3dp ehpk 3pxp")
    assert_equal "JBSWY3DPEHPK3PXP",
      Vault::Crypto.normalize_totp_secret("otpauth://totp/Site:me?secret=JBSWY3DPEHPK3PXP&issuer=Site")
    assert_raises(Vault::Crypto::Error) { Vault::Crypto.normalize_totp_secret("not!base32!") }
  end

  test "recovery codes avoid lookalikes and normalize forgivingly" do
    code = Vault::Crypto.generate_recovery_code

    assert_match(/\A[A-Z2-9]{6}(-[A-Z2-9]{6}){3}\z/, code)
    refute_match(/[ILO01U]/, code)
    assert_equal code.delete("-"), Vault::Crypto.normalize_recovery_code(code.downcase.tr("-", " "))
  end
end
