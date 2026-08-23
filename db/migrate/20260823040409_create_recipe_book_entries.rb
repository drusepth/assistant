class CreateRecipeBookEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_book_entries do |t|
      t.references :recipe_book, null: false, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.integer :position

      t.timestamps
    end
    add_index :recipe_book_entries, [ :recipe_book_id, :recipe_id ], unique: true
  end
end
