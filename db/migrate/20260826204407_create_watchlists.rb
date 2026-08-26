class CreateWatchlists < ActiveRecord::Migration[8.1]
  def change
    create_table :watchlists do |t|
      t.references :user, null: false, foreign_key: true
      t.references :section, null: false, foreign_key: true
      t.json :terms, default: [], null: false
      t.json :negatives, default: [], null: false
      # Terms that were asked for and refused, with why — the editor's
      # receipt, so a dropped word is explained rather than missing.
      t.json :dropped, default: [], null: false
      # Feeds this rule is paused for after it flooded them (W4).
      t.json :suspended_feed_ids, default: [], null: false
      t.string :source, default: "hand", null: false
      t.datetime :authored_at

      t.timestamps
    end

    add_index :watchlists, [ :user_id, :section_id ], unique: true
  end
end
