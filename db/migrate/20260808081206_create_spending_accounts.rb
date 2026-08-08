class CreateSpendingAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :spending_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "checking"
      t.string :last4
      t.json :csv_mapping
      t.timestamps
    end
  end
end
