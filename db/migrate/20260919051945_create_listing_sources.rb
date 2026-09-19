class CreateListingSources < ActiveRecord::Migration[8.1]
  def change
    create_table :listing_sources do |t|
      t.references :place, null: false, foreign_key: true
      t.string :url, null: false
      t.string :kind, null: false, default: "ics"
      t.string :provider
      t.string :title
      t.boolean :active, null: false, default: true
      t.string :etag
      t.string :last_modified
      t.datetime :last_fetched_at
      t.datetime :last_item_at
      t.integer :failure_count, null: false, default: 0
      t.string :last_error
      t.json :settings, null: false, default: {}
      t.text :credentials

      t.timestamps
    end
    add_index :listing_sources, %i[ place_id url ], unique: true
    add_index :listing_sources, :last_fetched_at
  end
end
