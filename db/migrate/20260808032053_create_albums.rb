class CreateAlbums < ActiveRecord::Migration[8.1]
  def change
    create_table :albums do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      # Optional explicit cover; the newest photo in the album otherwise.
      t.references :cover_photo, foreign_key: { to_table: :photos, on_delete: :nullify }

      t.timestamps
    end
  end
end
