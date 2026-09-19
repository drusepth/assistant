class CreatePlaces < ActiveRecord::Migration[8.1]
  def change
    create_table :places do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :country
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.integer :radius_km, null: false, default: 40
      t.integer :lead_days, null: false, default: 14
      t.boolean :alerts, null: false, default: true
      t.integer :position, null: false, default: 0
      t.datetime :last_opened_at

      t.timestamps
    end
    add_index :places, %i[ user_id position ]
  end
end
