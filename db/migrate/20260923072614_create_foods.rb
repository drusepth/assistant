class CreateFoods < ActiveRecord::Migration[8.1]
  def change
    # A kitchen's foods (D-food-catalog): the thing recipe ingredients, list
    # lines and pantry items are matched *on*. The model files each new line
    # onto one once; after that every match is a join.
    create_table :foods do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :name, null: false
      t.string :aisle
      t.string :default_location
      # One level: "chicken thighs" is a kind of "chicken", so it satisfies a
      # recipe asking for chicken — never the other way round.
      t.references :kind_of, foreign_key: { to_table: :foods, on_delete: :nullify }
      t.json :allergens, null: false, default: []
      # When the model filed it. Nil for a food made without one (each typed
      # key its own food) or by hand.
      t.datetime :filed_at
      t.timestamps
    end

    # Every normalized key that resolved to a food — the cache that makes a
    # line cost a model call once per kitchen, ever.
    create_table :food_aliases do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :food, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.timestamps
    end
    add_index :food_aliases, [ :kitchen_id, :key ], unique: true

    add_reference :shopping_list_items, :food, foreign_key: { on_delete: :nullify }

    # The household's own walk through their store — a user rule, so the
    # list reads in the order they shop.
    add_column :kitchens, :aisle_order, :json, null: false, default: []
  end
end
