class CreateLinkedAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :linked_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.json :credentials, null: false, default: {}
      t.json :disabled_scopes, null: false, default: []
      t.timestamps
    end
    add_index :linked_accounts, %i[ user_id provider ], unique: true
  end
end
