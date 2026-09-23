class CreateDiners < ActiveRecord::Migration[8.1]
  def change
    # Who eats from this kitchen, and what they can't (D-food-suggestions).
    # Written down by the household — never inferred from health data.
    create_table :diners do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.json :allergens, null: false, default: []
      # "vegetarian", "no pork" — prose, handed to the model to honour, or
      # shown as a reminder without one. Never parsed.
      t.string :diet_note
      t.timestamps
    end
  end
end
