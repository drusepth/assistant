class CreateSpendingRules < ActiveRecord::Migration[8.1]
  def change
    create_table :spending_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.references :budget_category, null: false, foreign_key: true
      t.string :matcher, null: false
      t.timestamps
      t.index %i[ user_id matcher ], unique: true
    end
  end
end
