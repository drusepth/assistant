class CreateSpottedHobbies < ActiveRecord::Migration[8.1]
  def change
    create_table :spotted_hobbies do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :reason
      t.json :feed_ids, default: [], null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :spotted_hobbies, [ :user_id, :name ], unique: true
  end
end
