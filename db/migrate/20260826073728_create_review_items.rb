class CreateReviewItems < ActiveRecord::Migration[8.1]
  def change
    create_table :review_items do |t|
      t.references :user, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true
      t.integer  :kind, null: false, default: 0
      t.text     :prompt, null: false
      t.text     :answer
      # FSRS memory state (D-review-scheduler) — only the scheduler writes these
      t.integer  :state, null: false, default: 0
      t.float    :stability
      t.float    :difficulty
      t.datetime :due_at
      t.integer  :reps, null: false, default: 0
      t.integer  :lapses, null: false, default: 0
      t.datetime :last_reviewed_at
      t.timestamps
    end
    add_index :review_items, %i[ user_id due_at ]
  end
end
