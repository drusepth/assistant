class CreatePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :photos do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.text :caption
      # EXIF DateTimeOriginal, falling back to upload time — the timeline
      # orders by when the photo was taken, not when it arrived (D30).
      t.datetime :taken_at, null: false
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :ingest_status, null: false, default: "queued"
      t.string :ingest_error

      t.timestamps
    end
    add_index :photos, [ :user_id, :taken_at ]
  end
end
