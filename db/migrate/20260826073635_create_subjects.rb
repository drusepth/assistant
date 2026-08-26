class CreateSubjects < ActiveRecord::Migration[8.1]
  def change
    create_table :subjects do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :title, null: false
      t.text    :description
      t.string  :commons_key            # curriculum-commons id it was seeded from; nil = generated/custom
      t.text    :interest_frame         # who's learning, through what lens — threads into every prompt
      t.integer :status, null: false, default: 0
      t.date    :target_date            # the learner's own pace anchor; nil = no pace pressure
      t.datetime :tree_built_at         # stamped when generation finished (even on failure), Goal pattern
      t.timestamps
    end
  end
end
