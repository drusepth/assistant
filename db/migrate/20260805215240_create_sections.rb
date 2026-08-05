class CreateSections < ActiveRecord::Migration[8.1]
  def change
    create_table :sections do |t|
      t.string :slug, null: false, index: { unique: true }
      t.string :name, null: false
      t.references :parent, foreign_key: { to_table: :sections }
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
