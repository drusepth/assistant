class CreateSectionTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :section_taggings do |t|
      t.references :section, null: false, foreign_key: true
      t.references :taggable, null: false, polymorphic: true

      t.timestamps
    end
    add_index :section_taggings, [ :section_id, :taggable_type, :taggable_id ],
      unique: true, name: "index_section_taggings_uniqueness"
  end
end
