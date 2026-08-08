class CreateVaultEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :vault_events do |t|
      # Whose vault the entry is about — the person who gets to read it.
      t.references :user, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      # Null for vault-wide events (emergency access); set for share/revoke.
      t.references :credential, foreign_key: true
      t.references :subject_user, foreign_key: { to_table: :users }
      t.string :action, null: false

      t.timestamps
    end
    add_index :vault_events, [ :user_id, :created_at ]
  end
end
