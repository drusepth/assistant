class MergeGoalsIntoTasksBoard < ActiveRecord::Migration[8.1]
  def change
    add_column :goals, :broken_down_at, :datetime
    change_column_default :goals, :status, from: 0, to: 1

    reversible do |dir|
      dir.up do
        # The goals kanban is gone, and with it the backlog state: a goal is
        # active until it's done. Existing goals count as already broken down
        # so they don't show a perpetual "breaking into steps" state.
        execute "UPDATE goals SET status = 1 WHERE status = 0"
        execute "UPDATE goals SET broken_down_at = updated_at"
      end
    end
  end
end
