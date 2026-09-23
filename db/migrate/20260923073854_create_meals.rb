class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    # The plan (D-kitchen): rows of the kitchen, not Events, so anyone who
    # cooks here can swap Tuesday and Wednesday. The Calendar draws them as
    # a band.
    create_table :meals do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.date :date, null: false
      t.string :slot, null: false, default: "dinner"
      # What's shown to everyone in the kitchen — copied from the recipe when
      # it's planned, so a cook who can't open the recipe still reads the
      # plan. "Leftovers", "takeout", "at Mum's" are meals with no recipe.
      t.string :title, null: false
      t.references :recipe, foreign_key: { on_delete: :nullify }
      t.integer :servings
      t.references :cook, foreign_key: { to_table: :users, on_delete: :nullify }
      # A meal that really is an event (the dinner party) links to one.
      t.references :event, foreign_key: { on_delete: :nullify }
      # When its ingredients went on a list, so "make the week's list" twice
      # doesn't add them twice. Cleared when the recipe or servings change.
      t.datetime :listed_at
      t.timestamps
    end
    add_index :meals, [ :kitchen_id, :date ]
  end
end
