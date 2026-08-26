class CreateStoryRoutings < ActiveRecord::Migration[8.1]
  def change
    create_table :story_routings do |t|
      t.references :feed_item, null: false, foreign_key: true
      t.references :section, null: false, foreign_key: true
      # The model's own one-line answer to "why is this here", shown on the
      # row. Never used as logic — it is what the reader reads.
      t.string :reason
      t.string :source, default: "model", null: false
      # A rejection is a tombstone, not a deletion: it keeps the story from
      # being routed here again, and it becomes an example the next batch
      # is shown.
      t.datetime :rejected_at

      t.timestamps
    end

    add_index :story_routings, [ :feed_item_id, :section_id ], unique: true
    add_index :story_routings, [ :section_id, :rejected_at ]
  end
end
