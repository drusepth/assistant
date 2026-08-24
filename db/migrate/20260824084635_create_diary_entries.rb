class CreateDiaryEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :diary_entries do |t|
      t.references :user, null: false, foreign_key: true

      # The one deliberate metadata leak (D-diary-vault): a locked diary can
      # draw its calendar and count its streak, and can show nothing else.
      t.date :entry_date, null: false

      # {title, body, mood, v:1} under the entry's item key, AES-256-GCM.
      t.binary :payload_ciphertext

      # The owner's own wrap rides the row rather than a key row: scheme byte
      # \x02 = under the user's diary key (the normal path, a GCM unwrap), or
      # \x01 = RSA to their public key (written while the vault was locked,
      # re-wrapped to \x02 on the next unlocked read).
      t.binary :owner_wrapped_item_key, null: false

      t.datetime :edited_at

      t.timestamps
    end

    add_index :diary_entries, [ :user_id, :entry_date ]
  end
end
