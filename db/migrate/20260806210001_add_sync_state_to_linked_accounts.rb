class AddSyncStateToLinkedAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :linked_accounts, :synced_at, :datetime
    add_column :linked_accounts, :sync_error, :string
  end
end
