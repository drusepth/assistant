# The email mirror (D30/D32, EMAIL_PLAN.md §4): owner-private cache of
# synced mailboxes, in the mirror database. References to primary-database
# rows (users, linked_accounts, people, promoted items) are soft integer
# ids — no cross-database foreign keys exist on purpose.
class CreateEmailMirror < ActiveRecord::Migration[8.1]
  def change
    create_table :email_folders do |t|
      t.integer :user_id, null: false
      t.integer :linked_account_id, null: false
      t.string :name, null: false
      t.string :role, null: false, default: "other"
      t.integer :uidvalidity
      t.integer :last_seen_uid, null: false, default: 0
      t.datetime :backfilled_at
      t.timestamps
      t.index %i[ linked_account_id name ], unique: true
      t.index :user_id
    end

    create_table :email_messages do |t|
      t.integer :user_id, null: false
      t.integer :linked_account_id, null: false
      t.integer :email_folder_id, null: false
      t.integer :uid, null: false
      t.string :message_id, null: false
      t.string :thread_key, null: false
      t.string :direction, null: false, default: "inbound"
      t.string :from_email
      t.string :from_name
      t.json :to_emails, null: false, default: []
      t.json :cc_emails, null: false, default: []
      t.string :subject
      t.datetime :sent_at
      t.integer :person_id
      t.string :snippet
      t.text :body_text
      t.json :attachments, null: false, default: []
      t.boolean :bulk, null: false, default: false
      t.boolean :seen, null: false, default: false
      t.boolean :answered, null: false, default: false
      t.json :triage
      t.integer :importance
      t.boolean :expects_reply
      t.datetime :triaged_at
      t.date :reply_wanted_by
      t.boolean :backfilled, null: false, default: false
      t.timestamps
      t.index %i[ linked_account_id message_id ], unique: true
      t.index %i[ user_id thread_key ]
      t.index %i[ user_id sent_at ]
      t.index %i[ user_id importance ]
      t.index :person_id
      t.index :email_folder_id
    end

    create_table :email_tombstones do |t|
      t.integer :linked_account_id, null: false
      t.string :message_id, null: false
      t.timestamps
      t.index %i[ linked_account_id message_id ], unique: true
    end

    # Promotion provenance (soft polymorphic item reference into the
    # primary database); rows double as prune keep-exceptions.
    create_table :email_message_items do |t|
      t.integer :email_message_id, null: false
      t.string :item_type, null: false
      t.integer :item_id, null: false
      t.timestamps
      t.index :email_message_id
    end
  end
end
