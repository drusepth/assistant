# E3 of the email plan: the feedback loop's memory (sender rules — user
# taught configuration, primary database, NOT mirror cache) and the
# per-user digest preferences.
class CreateEmailSenderRulesAndDigestPrefs < ActiveRecord::Migration[8.1]
  def change
    create_table :email_sender_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :email, null: false
      t.string :rule, null: false
      t.timestamps
      t.index %i[ user_id email ], unique: true
    end

    change_table :users, bulk: true do |t|
      t.json :mail_digest
      t.date :mail_digest_generated_on
      t.integer :mail_digest_hour, null: false, default: 8
      t.boolean :mail_digest_notify, null: false, default: false
    end
  end
end
