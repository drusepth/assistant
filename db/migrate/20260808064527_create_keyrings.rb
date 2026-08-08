class CreateKeyrings < ActiveRecord::Migration[8.1]
  def change
    create_table :keyrings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :key_salt, null: false
      t.integer :kdf_iterations, null: false
      t.binary :wrapped_key, null: false
      t.string :recovery_salt
      t.binary :recovery_wrapped_key
      t.datetime :recovery_confirmed_at
      t.text :public_key, null: false
      t.binary :wrapped_private_key, null: false
      t.datetime :reset_at

      t.timestamps
    end
  end
end
