class CreateCredentialKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :credential_keys do |t|
      t.references :credential, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.binary :wrapped_item_key, null: false

      t.timestamps
    end
    add_index :credential_keys, [ :credential_id, :user_id ], unique: true
  end
end
