class CreateTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :topics do |t|
      t.references :subject, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :topics }   # strand → topic
      t.integer :position, null: false, default: 1
      t.string  :title, null: false
      t.text    :summary               # what mastering this means — the teaching brief
      t.integer :mastery, null: false, default: 0
      t.string  :mastery_evidence      # quiz / tutor / teach_back / self_marked / placement
      t.date    :mastered_on
      t.references :goal, foreign_key: true   # the Learn-something bridge
      t.timestamps
    end
  end
end
