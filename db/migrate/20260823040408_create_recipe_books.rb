class CreateRecipeBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_books do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      # Optional explicit cover; the newest pictured recipe otherwise.
      t.references :cover_recipe, foreign_key: { to_table: :recipes, on_delete: :nullify }

      t.timestamps
    end
  end
end
