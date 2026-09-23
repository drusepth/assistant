class CreatePetVaccinations < ActiveRecord::Migration[8.1]
  def change
    create_table :pet_vaccinations do |t|
      t.references :pet, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false, default: "dose"
      t.string :vaccine_key
      t.string :name, null: false
      t.date :given_on, null: false
      t.date :due_on
      t.integer :duration_months
      t.references :vet, foreign_key: { to_table: :people, on_delete: :nullify }
      t.string :administered_by
      t.string :product
      t.string :lot_number
      t.string :tag_number
      t.string :site
      t.integer :series_dose
      t.text :reaction
      t.text :notes
      t.references :document, foreign_key: { on_delete: :nullify }
      t.references :event, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :pet_vaccinations, %i[ pet_id vaccine_key given_on ]
    add_index :pet_vaccinations, %i[ pet_id due_on ]
  end
end
