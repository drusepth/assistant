class CreateStudyLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :study_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :subject, foreign_key: true
      t.references :topic, foreign_key: true
      t.date    :on, null: false
      t.integer :minutes, null: false
      t.integer :activity, null: false, default: 0
      t.string  :note
      t.timestamps
    end
    add_index :study_logs, %i[ user_id on ]
  end
end
