class CreateFeedItems < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_items do |t|
      t.references :feed, null: false, foreign_key: true
      # The entry's own identity in its feed (guid/id, falling back to the
      # link): what makes a refresh idempotent.
      t.string :guid, null: false
      t.string :url
      t.string :title, null: false
      t.string :author
      t.text :summary
      t.string :image_url
      t.datetime :published_at

      # The reader's state, which is the whole point of a reader: what you
      # have seen, what you kept, and what you thought of it. The vote is
      # -1/0/1 and feeds the ranking's learned interest.
      t.datetime :read_at
      t.datetime :saved_at
      t.integer :vote, null: false, default: 0
      # The deterministic hobby-relevance score computed at ingest, so the
      # river can rank a window of items without re-reading every note.
      t.float :relevance, null: false, default: 0.0

      t.timestamps
    end

    add_index :feed_items, [ :feed_id, :guid ], unique: true
    add_index :feed_items, [ :feed_id, :published_at ]
    add_index :feed_items, :read_at
    add_index :feed_items, :saved_at
  end
end
