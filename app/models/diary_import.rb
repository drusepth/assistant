# An import in progress (DIARY_PLAN §6): the parsed entries waiting to be
# written, sealed under the user's diary key, plus how far through them we
# are.
#
# It exists because the obvious two implementations are both wrong here. A
# background job can't have the key. A plaintext tempfile would put the
# whole diary on disk in the clear, which is the one thing this container
# exists to prevent. So the staging is a sealed row, walked a batch per
# request — which also means a closed tab pauses an import rather than
# losing it.
class DiaryImport < ApplicationRecord
  AAD = "diary_import:v1".freeze

  # Enough to make a big import quick, small enough that one request stays
  # comfortably inside any proxy's patience.
  BATCH = 100

  # A cap with a number attached, so an implausible file gets a sentence
  # instead of a timeout.
  MAX_ENTRIES = 20_000

  belongs_to :user

  def self.stage!(user, rows, diary_key, skipped: 0, source_label: nil)
    create!(user: user, total: rows.size, skipped: skipped, source_label: source_label,
      payload_ciphertext: Vault::Crypto.encrypt(diary_key, rows.to_json, aad: AAD))
  end

  def rows(diary_key)
    JSON.parse(Vault::Crypto.decrypt(diary_key, payload_ciphertext, aad: AAD))
  rescue Vault::Crypto::Error, JSON::ParserError
    nil
  end

  # The next slice to write, or nil when the staged rows can't be opened —
  # which means the diary key changed under us (a password reset mid-import).
  def next_batch(diary_key, size: BATCH)
    rows(diary_key)&.slice(cursor, size) || []
  end

  def finished? = cursor >= total

  def percent = total.zero? ? 100 : ((cursor.to_f / total) * 100).round
end
