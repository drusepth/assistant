class CreatePetFoods < ActiveRecord::Migration[8.1]
  def change
    create_table :pet_foods do |t|
      t.references :pet, null: false, foreign_key: true

      t.string :name, null: false
      t.string :brand
      t.string :form, null: false, default: "dry"

      # The two numbers the shelf is for (D-pet-food-shelf): a bag divided by
      # a daily amount is a reorder date, and a bag's price over its days is a
      # monthly cost. Decimals, because a cat eats 60g a day.
      t.decimal :amount_per_day, precision: 8, scale: 2
      t.string :unit, null: false, default: "g"
      t.decimal :package_amount, precision: 10, scale: 2
      t.integer :package_cost_cents

      # Ending a food rather than editing it is what keeps a diet history —
      # the thing a vet actually asks for.
      t.date :started_on, null: false
      t.date :ended_on

      # When the current bag was opened. Without it a reorder date can only be
      # counted from `started_on`, which drifts a bag further out every month.
      t.date :opened_on

      t.text :notes

      t.timestamps
    end
  end
end
