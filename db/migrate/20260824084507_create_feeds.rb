class CreateFeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :feeds do |t|
      t.references :user, null: false, foreign_key: true
      # What we fetch, and where a human goes to read the source. The paste
      # can be either (D-feed-reader): discovery resolves a site URL to its
      # feed, so `url` is always the machine-readable one.
      t.string :url, null: false
      t.string :site_url
      t.string :title
      t.text :description
      # The user's own name for it, when the feed's own title is noise.
      t.string :label
      t.string :kind, null: false, default: "rss"
      t.boolean :active, null: false, default: true

      # Politeness and honesty about the last fetch: a feed that has been
      # 404ing for a week says so on its row rather than going quiet.
      t.datetime :last_fetched_at
      t.datetime :last_item_at
      t.string :last_error
      t.integer :failure_count, null: false, default: 0

      t.timestamps
    end

    add_index :feeds, [ :user_id, :url ], unique: true
    add_index :feeds, :last_fetched_at
  end
end
