class CreateHobbyBriefs < ActiveRecord::Migration[8.1]
  def change
    create_table :hobby_briefs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :section, null: false, foreign_key: true
      # What this hobby means, in prose, for the model that reads stories.
      # Not a rule, not a pattern — a sentence a person would say.
      t.text :description
      t.boolean :enabled, default: true, null: false
      t.datetime :authored_at

      t.timestamps
    end

    add_index :hobby_briefs, [ :user_id, :section_id ], unique: true
  end
end
