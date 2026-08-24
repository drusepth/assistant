# Autosave without undo is a diary that can quietly eat words: a bad save,
# a paste over a selection, a phone in a pocket. Revisions are the cheapest
# possible insurance — the previous payload, sealed under the entry's *own*
# item key, so this adds no key management and nothing new can be lost.
class CreateDiaryRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :diary_revisions do |t|
      t.references :diary_entry, null: false, foreign_key: true

      # {title, body, mood, v:1} under the entry's item key. Its own AAD, so
      # a revision's ciphertext can't be passed off as the live entry.
      t.binary :payload_ciphertext, null: false

      t.timestamps
    end

    add_index :diary_revisions, [ :diary_entry_id, :created_at ]
  end
end
