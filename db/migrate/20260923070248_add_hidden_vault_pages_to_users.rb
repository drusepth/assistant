class AddHiddenVaultPagesToUsers < ActiveRecord::Migration[8.1]
  def change
    # Stores what's switched *off*, so a vault page added later arrives on
    # for everyone rather than hidden from everyone (D-vault-picker).
    add_column :users, :hidden_vault_pages, :json, default: [], null: false
  end
end
