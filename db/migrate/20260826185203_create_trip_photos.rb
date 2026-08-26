class CreateTripPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_photos do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :photo, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :trip_photos, [ :trip_id, :photo_id ], unique: true
  end
end
