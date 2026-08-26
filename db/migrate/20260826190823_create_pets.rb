class CreatePets < ActiveRecord::Migration[8.1]
  def change
    create_table :pets do |t|
      t.references :user, null: false, foreign_key: true
      # The pet's own lens (D-pet-primitive): a custom child of People,
      # created with the pet, which is what makes "about Rex" an ordinary
      # tag rather than a new join table.
      t.references :section, null: false, foreign_key: true, index: { unique: true }
      t.references :vet, foreign_key: { to_table: :people }

      t.string :name, null: false
      t.string :species, null: false
      t.string :breed
      t.string :sex
      t.string :color
      t.string :microchip

      # Usually a guess for a rescue, so the app says "about 4" rather than
      # printing a birthday it was never told.
      t.date :born_on
      t.boolean :born_on_estimated, null: false, default: false
      t.date :adopted_on

      # A single current weight, not a time series (Q-pet-metrics): tools
      # want the number as context; a chart is a primitive with no consumer.
      t.decimal :weight_kg, precision: 6, scale: 2

      # The end of a life, handled once and properly: every radar, watcher
      # and reorder stops, and nothing is deleted.
      t.date :died_on
      t.date :left_on

      t.text :notes

      t.timestamps
    end
  end
end
