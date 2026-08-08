class CreateEmergencyContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :emergency_contacts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :contact_user, null: false, foreign_key: { to_table: :users }
      t.binary :wrapped_vault_key, null: false
      t.integer :wait_days, null: false, default: 7
      t.datetime :requested_at
      t.datetime :released_at

      t.timestamps
    end
    add_index :emergency_contacts, [ :user_id, :contact_user_id ], unique: true
  end
end
