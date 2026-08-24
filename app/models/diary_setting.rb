# The per-user diary key (D-diary-vault), wrapped under the vault key.
#
# Why a tier the password vault doesn't have: a credential is decrypted one
# reveal-click at a time, so an RSA unwrap per read costs nothing a person
# notices. A diary index wants titles for a screenful and search wants every
# entry, and RSA-3072 on the Pi-class boxes this app targets is ~10-20ms a
# go — seconds per page view by the second year of writing. Entry item keys
# therefore ride a symmetric wrap under this key, and a whole journal opens
# in one GCM unwrap each.
#
# It also gives the diary its own seam: re-keying the diary, or one day
# putting it behind a second passphrase, is a rewrap of this row rather than
# of every entry.
class DiarySetting < ApplicationRecord
  CONTENT_KEY_AAD = "diary:v1:content-key".freeze

  belongs_to :user

  # Find, create, or heal the diary key for an unlocked vault. Healing is
  # the password-reset case: the vault key that wrapped this one is gone, so
  # every existing entry is sealed forever and a fresh key is minted so
  # writing works again. The crypto decides that, not a flag — the stamp is
  # only so the UI can say when it happened.
  def self.unlock_for(user, vault_key)
    setting = find_or_initialize_by(user: user)

    if setting.persisted?
      key = setting.content_key(vault_key)
      key ? [ setting, key ] : [ setting, setting.rekey!(vault_key) ]
    else
      key = Vault::Crypto.random_key
      setting.wrapped_content_key = wrap(key, vault_key)
      setting.save!
      [ setting, key ]
    end
  end

  def self.wrap(content_key, vault_key)
    Vault::Crypto.encrypt(vault_key, content_key, aad: CONTENT_KEY_AAD)
  end

  def content_key(vault_key)
    return nil if vault_key.blank?

    Vault::Crypto.decrypt(vault_key, wrapped_content_key, aad: CONTENT_KEY_AAD)
  rescue Vault::Crypto::Error
    nil
  end

  def rekey!(vault_key)
    key = Vault::Crypto.random_key
    update!(wrapped_content_key: self.class.wrap(key, vault_key),
      content_key_reset_at: content_key_reset_at || Time.current)
    key
  end

  def lost_entries? = content_key_reset_at.present?
end
