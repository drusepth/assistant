class CreatePantryItems < ActiveRecord::Migration[8.1]
  def change
    # What's in the kitchen (D-kitchen, D-pantry): presence is the signal
    # and the amount is prose (Q-pantry-quantities, resolved: presence only
    # for now).
    create_table :pantry_items do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :food, foreign_key: { on_delete: :nullify }
      t.string :item, null: false
      t.string :item_key, null: false
      t.string :quantity_note
      t.string :location, null: false, default: "pantry"
      t.date :expires_on
      t.date :opened_on
      t.references :added_by, foreign_key: { to_table: :users, on_delete: :nullify }
      # The list line this came from, when checking it off put it away — so
      # un-checking it (the undo) takes it back out.
      t.references :shopping_list_item, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :pantry_items, [ :kitchen_id, :location ]
    add_index :pantry_items, [ :kitchen_id, :expires_on ]

    # Checking a line off the list puts it in the kitchen — the one change
    # that keeps a pantry list true without anybody maintaining it. Off for
    # households that don't keep one.
    add_column :kitchens, :put_away_on_check, :boolean, null: false, default: true
  end
end
