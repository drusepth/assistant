class AddRecapRequestedAtToToolRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_runs, :recap_requested_at, :datetime
  end
end
