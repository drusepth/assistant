class CreateStays < ActiveRecord::Migration[8.1]
  def change
    create_table :stays do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :location, null: false
      t.string :name
      t.string :kind, null: false, default: "airbnb"
      t.string :booking_status, null: false, default: "planned"
      t.date :check_in, null: false
      t.date :check_out, null: false
      t.string :url
      t.string :confirmation_code
      t.text :notes

      t.timestamps
    end
    add_index :stays, [ :trip_id, :check_in ]
  end
end
