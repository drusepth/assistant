# A previous version of one entry (DIARY_PLAN §4.4), sealed under that
# entry's own item key — so a revision costs no new key, dies with the entry,
# and is exactly as readable (and exactly as lost) as the entry it belongs to.
#
# Its own AAD keeps the two apart: a revision's ciphertext moved into the
# live `payload_ciphertext` column fails its tag rather than quietly becoming
# the current entry.
class DiaryRevision < ApplicationRecord
  AAD = "diary_revision:v1".freeze

  # Enough to undo a bad afternoon, not so many that a decade of daily
  # editing turns one entry into a thousand rows.
  KEEP = 20

  # Autosave fires every few seconds, so snapshotting every write would mint
  # twenty near-identical rows in a couple of minutes and prune away the only
  # version anyone would want back. One per writing session is the useful
  # granularity: what this entry looked like *before today's sitting*.
  MIN_INTERVAL = 30.minutes

  belongs_to :diary_entry

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # `force:` for a restore, which replaces the whole payload deliberately —
  # the throttle would skip exactly the snapshot most worth having, the one
  # taken moments after the edit being undone.
  def self.seal!(entry, payload, item_key, force: false)
    return if payload.blank?
    return if !force && where(diary_entry: entry).where(created_at: MIN_INTERVAL.ago..).exists?

    create!(diary_entry: entry,
      payload_ciphertext: Vault::Crypto.encrypt(item_key, payload.merge("v" => 1).to_json, aad: AAD))
    prune!(entry)
  end

  def self.prune!(entry)
    keep = where(diary_entry: entry).newest_first.limit(KEEP).pluck(:id)
    where(diary_entry: entry).where.not(id: keep).delete_all
  end

  def open(item_key)
    JSON.parse(Vault::Crypto.decrypt(item_key, payload_ciphertext, aad: AAD)).except("v")
  rescue Vault::Crypto::Error, JSON::ParserError
    nil
  end
end
