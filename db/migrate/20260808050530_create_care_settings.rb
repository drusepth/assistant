class CreateCareSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :care_settings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind_key, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :interval_months
      t.string :label

      t.timestamps
    end
    add_index :care_settings, [ :user_id, :kind_key ], unique: true
  end
end
