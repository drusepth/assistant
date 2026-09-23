class CreateShoppingLists < ActiveRecord::Migration[8.1]
  def change
    # A kitchen's lists (D-kitchen): "Weekly", "Costco", "Saturday party".
    # Rows of the kitchen, so anyone who can cook there can edit them.
    create_table :shopping_lists do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # One line of a list. Parsed with the recipe parser's line reader, so
    # "2 tins chickpeas" here and in a recipe are the same shape.
    # `added_by`/`checked_by` are for display ("Sam added this"), never for
    # permission — a line has no owner.
    create_table :shopping_list_items do |t|
      t.references :shopping_list, null: false, foreign_key: true
      t.string :item, null: false
      t.string :item_key, null: false
      t.decimal :quantity, precision: 10, scale: 3
      t.string :unit
      t.string :note
      t.references :recipe, foreign_key: { on_delete: :nullify }
      t.references :added_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :checked_at
      t.references :checked_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :shopping_list_items, [ :shopping_list_id, :checked_at ]
  end
end
