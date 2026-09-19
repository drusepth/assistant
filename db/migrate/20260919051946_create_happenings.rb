class CreateHappenings < ActiveRecord::Migration[8.1]
  def change
    create_table :happenings do |t|
      t.references :listing_source, null: false, foreign_key: true
      t.string :kind, null: false, default: "event"
      t.string :provenance, null: false, default: "listed"
      t.string :uid, null: false
      t.string :series_uid
      t.string :title, null: false
      t.text :description
      t.string :location
      t.string :url
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :all_day, null: false, default: false
      t.date :expires_on
      t.datetime :last_seen_at
      t.datetime :withdrawn_at
      t.decimal :distance_km, precision: 8, scale: 1
      t.boolean :out_of_range, null: false, default: false
      t.references :event, foreign_key: true
      t.references :task, foreign_key: true
      t.datetime :hidden_at
      t.datetime :matched_at

      t.timestamps
    end
    add_index :happenings, %i[ listing_source_id uid ], unique: true
    add_index :happenings, %i[ listing_source_id starts_at ]
    add_index :happenings, :series_uid
    add_index :happenings, :matched_at
  end
end
