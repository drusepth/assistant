class CreatePhotoPeople < ActiveRecord::Migration[8.1]
  def change
    create_table :photo_people do |t|
      t.references :photo, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.timestamps
    end
    add_index :photo_people, [ :photo_id, :person_id ], unique: true
  end
end
