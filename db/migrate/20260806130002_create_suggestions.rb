class CreateSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :suggestions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body
      t.string :kind, null: false, default: "nudge"
      t.string :watcher_slug, null: false
      t.string :status, null: false, default: "pending"
      t.date :snoozed_until
      t.json :action, default: {}, null: false
      t.string :fingerprint, null: false

      t.timestamps
    end

    add_index :suggestions, [ :user_id, :fingerprint ], unique: true
    add_index :suggestions, [ :user_id, :status ]
  end
end
