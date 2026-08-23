class CreateRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :recipes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      # Prose, rendered as numbered steps: nothing joins to step 4
      # (D-recipe-primitive). Ingredients get rows because the pantry match,
      # the grocery list, and scaling all key off their quantities.
      t.text :directions
      t.text :notes
      t.string :source_name
      t.string :source_url
      t.integer :servings
      t.integer :prep_minutes
      t.integer :cook_minutes
      t.boolean :favorite, null: false, default: false
      # The whole cook log: one tap, and what the later rut/rotation
      # watchers read.
      t.date :last_cooked_on
      t.integer :times_cooked, null: false, default: 0

      t.timestamps
    end
    add_index :recipes, [ :user_id, :title ]
  end
end
