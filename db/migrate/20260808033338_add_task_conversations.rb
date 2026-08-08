class AddTaskConversations < ActiveRecord::Migration[8.1]
  def change
    # Capture-time coaching questions (D30): the opening the task page's
    # conversation shows without spending a model call.
    add_column :tasks, :guiding_questions, :json, default: [], null: false
    # The task's answer — where a mental task's outcome is kept.
    add_column :tasks, :resolution, :text
    # What a run is about (D30): a chat run bound to a task lives on the
    # task's page. Nullable — ordinary tool runs have no subject.
    add_reference :tool_runs, :subject, polymorphic: true
  end
end
