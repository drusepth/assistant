class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.datetime :starts_at, null: false, index: true
      t.datetime :ends_at
      t.boolean :all_day, null: false, default: false
      t.string :location

      t.timestamps
    end
  end
end
