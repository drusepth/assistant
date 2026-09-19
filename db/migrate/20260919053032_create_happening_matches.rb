class CreateHappeningMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :happening_matches do |t|
      t.references :happening, null: false, foreign_key: true
      t.string :target, null: false
      t.references :section, foreign_key: true
      t.string :reason
      t.string :source, null: false, default: "model"
      t.datetime :rejected_at

      t.timestamps
    end
    add_index :happening_matches, %i[ happening_id target ], unique: true
    add_index :happening_matches, %i[ section_id rejected_at ]
  end
end
