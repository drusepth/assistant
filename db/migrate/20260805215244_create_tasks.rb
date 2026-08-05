class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, foreign_key: true
      t.string :title, null: false
      t.text :notes
      t.date :due_on, index: true
      t.datetime :completed_at

      t.timestamps
    end
  end
end
