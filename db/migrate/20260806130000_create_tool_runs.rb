class CreateToolRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :tool_slug, null: false
      t.json :inputs, null: false, default: {}
      t.string :status, null: false, default: "queued"
      t.string :error
      t.json :output, null: false, default: {}
      t.timestamps
    end
    add_index :tool_runs, %i[ user_id created_at ]

    create_table :tool_run_items do |t|
      t.references :tool_run, null: false, foreign_key: true
      t.references :item, polymorphic: true, null: false
      t.timestamps
    end
    add_index :tool_run_items, %i[ tool_run_id item_type item_id ], unique: true
  end
end
