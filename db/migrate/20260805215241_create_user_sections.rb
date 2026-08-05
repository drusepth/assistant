class CreateUserSections < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :section, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
    add_index :user_sections, [ :user_id, :section_id ], unique: true
  end
end
