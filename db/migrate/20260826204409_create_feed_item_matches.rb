class CreateFeedItemMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_item_matches do |t|
      t.references :feed_item, null: false, foreign_key: true
      t.references :section, null: false, foreign_key: true
      # Which terms fired, so the row can say why it is here and a
      # correction knows what to blame.
      t.json :terms, default: [], null: false
      t.string :source, default: "match", null: false
      # A rejected match is a tombstone, not a deletion: it stops the row
      # coming back on the next backfill, and it is the evidence a rule
      # correction reads.
      t.datetime :rejected_at

      t.timestamps
    end

    add_index :feed_item_matches, [ :feed_item_id, :section_id ], unique: true
    add_index :feed_item_matches, [ :section_id, :rejected_at ]
  end
end
