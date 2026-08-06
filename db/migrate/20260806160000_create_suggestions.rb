class CreateSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :suggestions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :watcher_slug, null: false
      t.string :fingerprint, null: false
      t.string :kind, null: false, default: "nudge"
      t.string :title, null: false
      t.text :body
      t.json :action, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.datetime :snoozed_until
      t.timestamps
    end
    add_index :suggestions, %i[ user_id status ]
    add_index :suggestions, %i[ user_id fingerprint ]
  end
end
