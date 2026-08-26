class CreateTripLegs < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_legs do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :kind, null: false, default: "flight"
      t.string :booking_status, null: false, default: "planned"
      t.date :starts_on, null: false
      t.date :ends_on
      t.datetime :departs_at
      t.string :origin
      t.string :destination
      t.string :carrier
      t.string :confirmation_code
      t.string :url
      t.text :notes

      t.timestamps
    end
    add_index :trip_legs, [ :trip_id, :starts_on ]
  end
end
