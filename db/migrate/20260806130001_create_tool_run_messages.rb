class CreateToolRunMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_run_messages do |t|
      t.references :tool_run, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false

      t.timestamps
    end

    add_index :tool_run_messages, [ :tool_run_id, :created_at ]
  end
end
