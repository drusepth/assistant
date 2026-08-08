class CreateCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false, default: "login"
      t.string :name, null: false
      t.string :username
      t.string :url
      t.binary :secrets_ciphertext
      t.boolean :totp_present, null: false, default: false
      t.datetime :secret_changed_at
      t.datetime :last_used_at

      t.timestamps
    end
  end
end
