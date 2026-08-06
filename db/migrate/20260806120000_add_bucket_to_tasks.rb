class AddBucketToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :bucket, :integer, default: 0, null: false
    add_index :tasks, :bucket

    # Open tasks that are already due belong in the Today column from day one.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE tasks SET bucket = 1
          WHERE completed_at IS NULL AND due_on IS NOT NULL AND due_on <= '#{Date.current.iso8601}'
        SQL
      end
    end
  end
end
