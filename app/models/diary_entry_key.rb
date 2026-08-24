# Decryptability for a *grantee* of one diary entry (D-diary-vault): the
# entry's item key wrapped to their public key, exactly as CredentialKey.
# The owner never has a row here — their wrap rides the entry itself under
# the diary key — so this table is precisely the set of people who are not
# the author, which is also the answer to "who else can read this".
class DiaryEntryKey < ApplicationRecord
  belongs_to :diary_entry
  belongs_to :user

  validates :user_id, uniqueness: { scope: :diary_entry_id }
end
