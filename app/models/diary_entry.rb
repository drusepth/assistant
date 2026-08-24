# One day's writing (D-diary-vault): the Album/Credential precedent taken a
# tier further. `Visible`, never `Sectionable` — so no categorizer, no tool
# context, no dashboard, and no section-level grant can ever reach it — and,
# unlike a credential, **no metadata tier at all**. A diary's title is as
# sensitive as its body, so title, body and the user's own mood word all
# live inside the sealed payload; `entry_date` is the only plaintext, which
# is what lets a locked diary draw its calendar and show nothing else.
#
# The owner's item-key wrap rides this row rather than a key row, under the
# per-user diary key (see DiarySetting) — the tier that makes reading a
# whole journal cheap. `diary_entry_keys` therefore holds grantees only.
class DiaryEntry < ApplicationRecord
  PAYLOAD_AAD = "diary_entry:v1".freeze
  ITEM_KEY_AAD = "diary_entry:v1:item-key".freeze

  # First byte of `owner_wrapped_item_key`. Writing is allowed while the
  # vault is locked (capture must never wait on a password), and a locked
  # write can only reach the public key — so the wrap says which it is.
  SCHEME_RSA = "\x01".b.freeze          # written locked; RSA-OAEP to the owner
  SCHEME_DIARY_KEY = "\x02".b.freeze    # the normal path; GCM under the diary key

  include Visible
  include VaultSealed

  seals payload: :payload_ciphertext, keys: :diary_entry_keys, aad: PAYLOAD_AAD

  has_many :diary_entry_keys, dependent: :destroy
  has_many :vault_events, as: :subject, dependent: :destroy

  validates :entry_date, presence: true

  scope :newest_first, -> { order(entry_date: :desc, created_at: :desc) }
  scope :on, ->(date) { where(entry_date: date) }
  scope :in_month, ->(month) { where(entry_date: month.beginning_of_month..month.end_of_month) }

  # The same calendar day in any year — what "on this day" is built from.
  # Plaintext dates are exactly what makes this a cheap index scan instead
  # of a decrypt of the whole journal.
  scope :on_day_of_year, ->(date) {
    where("strftime('%m-%d', entry_date) = ?", date.strftime("%m-%d"))
  }

  # Held only for the duration of one seal (see #seal!): present takes the
  # cheap wrap, absent takes the capture-while-locked path. Deliberately not
  # a durable attribute — a diary key left lying on an instance would let a
  # later call decrypt with a key the caller never proved it had.
  attr_accessor :diary_key
  private :diary_key=

  # A password reset without the recovery code kills the vault key, and with
  # it the diary key every entry's owner wrap sits under. Nothing is deleted
  # — the entries stay, sealed for good — so on top of dropping the wraps
  # this user held on *other* people's entries, record when the break
  # happened so the diary can say so instead of silently failing to open.
  def self.mark_lost_on_reset!(user)
    super
    user.diary_setting&.update!(content_key_reset_at: Time.current)
  end

  # Seal a payload under a fresh item key. The diary key is borrowed for
  # exactly this call: with one, the owner's wrap goes under it; without,
  # capture still works and the wrap goes to their public key instead.
  def seal!(payload, diary_key: nil)
    self.diary_key = diary_key
    write_secrets!(payload)
  ensure
    self.diary_key = nil
  end

  # Both reads run through here (D-vault-crypto's one-decrypt-path rule):
  # the owner via the record's own wrap, a grantee via their key row. The
  # diary key is passed rather than looked up when the caller already holds
  # it — reading a screenful of entries shouldn't be a screenful of queries.
  def unwrap_item_key(viewer, vault_key, diary_key: nil)
    return super(viewer, vault_key) unless viewer.id == user_id

    unwrap_owner_item_key(viewer, vault_key, diary_key)
  end

  # Whether *this* viewer can still open the entry. For the owner that is a
  # crypto question rather than a row question — a password reset without
  # the recovery code kills the diary key, and every entry under it is
  # sealed for good with nothing deleted to show for it.
  def lost_for?(viewer, vault_key, diary_key: nil)
    unwrap_item_key(viewer, vault_key, diary_key: diary_key).nil?
  end

  # Key rows only ever hold grantees, so row-absence says nothing about the
  # owner (see #lost_for?).
  def secret_lost_for?(viewer) = viewer.id != user_id && super

  def wrapped_while_locked? = owner_wrapped_item_key.to_s.b.byteslice(0) == SCHEME_RSA

  # An entry written while locked carries an RSA wrap; the first unlocked
  # read moves it onto the diary key so later reads are cheap. Opportunistic
  # by design — it is a performance repair, never a correctness one, so a
  # failure here must leave the entry readable.
  def rewrap_to_diary_key!(item_key, diary_key)
    return false unless wrapped_while_locked? && diary_key.present?

    update_column(:owner_wrapped_item_key, wrap_under_diary_key(item_key, diary_key))
    true
  end

  private
    def unwrap_owner_item_key(viewer, vault_key, diary_key)
      blob = owner_wrapped_item_key.to_s.b
      wrapped = blob.byteslice(1..).to_s

      case blob.byteslice(0)
      when SCHEME_DIARY_KEY
        key = diary_key.presence || viewer_diary_key(viewer, vault_key) or return nil
        Vault::Crypto.decrypt(key, wrapped, aad: ITEM_KEY_AAD)
      when SCHEME_RSA
        return nil if vault_key.blank?

        Vault::Crypto.rsa_unwrap(viewer.keyring.private_key(vault_key), wrapped)
      end
    rescue Vault::Crypto::Error
      nil
    end

    # Deliberately a query rather than `viewer.diary_setting`: the
    # association memoizes, and a re-key (or a first-ever unlock) during the
    # same request would leave a caller reading a wrap that no longer
    # exists. Callers that read more than one entry go through
    # Diary::Session, which holds the key and never lands here.
    def viewer_diary_key(viewer, vault_key)
      DiarySetting.find_by(user_id: viewer.id)&.content_key(vault_key)
    end

    def seal_item_key_on_record(holder, item_key)
      return false unless holder.id == user_id

      self.owner_wrapped_item_key =
        if diary_key.present?
          wrap_under_diary_key(item_key, diary_key)
        else
          SCHEME_RSA + Vault::Crypto.rsa_wrap(holder.keyring.public_key, item_key)
        end
      true
    end

    def wrap_under_diary_key(item_key, key)
      SCHEME_DIARY_KEY + Vault::Crypto.encrypt(key, item_key, aad: ITEM_KEY_AAD)
    end

    def after_sealing(payload)
      self.edited_at = Time.current
    end
end
