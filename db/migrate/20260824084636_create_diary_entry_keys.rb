class CreateDiaryEntryKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :diary_entry_keys do |t|
      t.references :diary_entry, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      # Grantee wraps only (W4) — the owner's rides diary_entries. RSA-OAEP
      # to the grantee's public key, exactly as credential_keys.
      t.binary :wrapped_item_key, null: false

      t.timestamps
    end

    add_index :diary_entry_keys, [ :diary_entry_id, :user_id ], unique: true
  end
end
