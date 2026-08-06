class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :relationship
      t.string :email
      t.string :phone
      t.date :birthday
      t.text :notes
      t.references :linked_user, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
