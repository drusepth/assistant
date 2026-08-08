class CreateBudgetCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :budget_categories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :group, null: false, default: "needs"
      t.integer :monthly_target_cents
      t.string :target_set_by
      t.integer :position
      t.datetime :archived_at
      t.timestamps
      t.index %i[ user_id name ], unique: true
    end
  end
end
