class CreateAppErrors < ActiveRecord::Migration[8.1]
  def change
    create_table :app_errors do |t|
      t.string :source, null: false
      t.string :error_class, null: false
      t.text :message, null: false
      t.text :backtrace
      t.json :context, default: {}, null: false
      t.references :user, foreign_key: true

      t.timestamps
    end

    add_index :app_errors, :created_at
    add_index :app_errors, [ :source, :created_at ]
  end
end
