# The spending ledger (D-spending-mirror, MONEY.md §2): the second mirror
# source. Statement files are vault Documents fanned into these rows;
# manual quick-log and (later) email-receipt rows join them. References
# to primary-database rows (users, accounts, categories, statement
# documents) are soft integer ids — no cross-database foreign keys.
class CreateSpendingMirror < ActiveRecord::Migration[8.1]
  def change
    create_table :spending_transactions do |t|
      t.integer :user_id, null: false
      t.integer :spending_account_id, null: false
      t.date :occurred_on, null: false
      t.integer :amount_cents, null: false
      t.string :descriptor
      t.string :merchant
      t.integer :budget_category_id
      t.string :categorized_by
      t.string :source, null: false, default: "statement"
      t.string :external_id
      t.string :fingerprint, null: false
      t.integer :document_id
      t.boolean :transfer, null: false, default: false
      t.string :transfer_set_by
      t.timestamps
      t.index %i[ spending_account_id fingerprint ], unique: true
      t.index %i[ spending_account_id external_id ]
      t.index %i[ user_id occurred_on ]
      t.index %i[ user_id merchant ]
      t.index %i[ user_id budget_category_id ]
    end

    # A deletion that stays deleted (the EmailTombstone pattern): imports
    # skip tombstoned fingerprints, so removing a mis-parsed or private row
    # can't be undone by re-importing the same statement.
    create_table :spending_tombstones do |t|
      t.integer :spending_account_id, null: false
      t.string :fingerprint, null: false
      t.timestamps
      t.index %i[ spending_account_id fingerprint ], unique: true
    end
  end
end
