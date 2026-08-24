class CreateDiarySettings < ActiveRecord::Migration[8.1]
  def change
    create_table :diary_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      # The per-user diary key, wrapped under the vault key (D-diary-vault):
      # what makes reading a whole journal a GCM unwrap per entry instead of
      # an RSA one.
      t.binary :wrapped_content_key, null: false

      # Entries written before this are sealed under a diary key that no
      # longer exists — the whole-diary loss marker a password reset leaves
      # behind. Whole-diary because there is one diary key, so it cannot
      # drift out of sync with any single entry.
      t.datetime :content_key_reset_at

      # §7: emergency access opens the passwords vault and not the diary
      # unless the owner says otherwise. App policy, not cryptography.
      t.boolean :emergency_included, null: false, default: false

      t.boolean :prompts_enabled, null: false, default: true

      t.timestamps
    end
  end
end
