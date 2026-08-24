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

      # The only state a reader needs: what you've seen, and what you kept.
      # There is no score and no vote — the river is chronological, and this
      # is one person's reading list, not a rating system (D-feed-reader).
      t.datetime :read_at
      t.datetime :saved_at

      t.timestamps
    end

    add_index :feed_items, [ :feed_id, :guid ], unique: true
    add_index :feed_items, [ :feed_id, :published_at ]
    add_index :feed_items, :read_at
    add_index :feed_items, :saved_at
  end
end
