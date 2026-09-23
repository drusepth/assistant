# The Vault picker (D-vault-picker): the Your life picker's twin for the
# sidebar's Vault group. One card per VaultPage, each switched on or off
# on its own; hiding one deletes nothing and leaves its URL working.
class VaultPagesController < ApplicationController
  def index
    @pages = VaultPage::ALL
    @has_email_account = Current.user.linked_accounts.where(provider: "email").exists?
  end

  def update
    page = VaultPage.find!(params[:slug])
    enabled = params[:enabled] == "1"
    Current.user.set_vault_page_enabled!(page.slug, enabled)

    # Same trick as the Your life picker: redirecting to this page is a
    # Turbo refresh, which morphs the card and the sidebar in place.
    redirect_to vault_pages_path, notice: enabled ?
      "#{page.name} is on — it's in your sidebar." :
      "#{page.name} is off. Nothing in it was deleted; turn it back on any time."
  end
end
