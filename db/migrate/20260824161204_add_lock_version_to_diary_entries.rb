# Autosave makes two-tab collisions ordinary rather than exotic: both tabs
# save on their own timer, and without a version the slower one silently
# overwrites whatever the other wrote. Rails' optimistic locking turns that
# into a refusal the writer can see.
class AddLockVersionToDiaryEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :diary_entries, :lock_version, :integer, null: false, default: 0
  end
end
