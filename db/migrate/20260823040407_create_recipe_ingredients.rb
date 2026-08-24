class CreateRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_ingredients do |t|
      t.references :recipe, null: false, foreign_key: true
      t.integer :position, null: false
      # nil quantity is normal ("salt to taste") — the parser never invents
      # a number, and an unquantified line is passed through untouched by
      # scaling.
      t.decimal :quantity, precision: 10, scale: 3
      t.string :unit
      t.string :item, null: false
      # The match key for the pantry and the grocery list (D-pantry):
      # downcased, singular, descriptors stripped.
      t.string :item_key, null: false
      t.string :note
      # The line exactly as typed — parsing is lossless, so the edit form
      # shows the user their own words back.
      t.string :raw, null: false
      t.boolean :optional, null: false, default: false

      t.timestamps
    end
    add_index :recipe_ingredients, [ :recipe_id, :position ]
    add_index :recipe_ingredients, :item_key
  end
end
