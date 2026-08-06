# Connect/disconnect outside services and tune what each one shares (D21).
# Strictly per-user: links belong to whoever created them, and scope edits
# only ever touch Current.user's own rows.
class LinkedAccountsController < ApplicationController
  def create
    provider = params[:provider].to_s
    settings = LinkedAccount::PROVIDERS[provider]
    return redirect_to settings_path, alert: "Unknown service." unless settings

    account = Current.user.linked_accounts.build(provider: provider, credentials: credential_params(settings))
    if account.save
      notice = "#{account.label} linked. The assistant has full access — adjust what it can use below."
      if account.syncable?
        SyncLinkedAccountJob.perform_later(account)
        notice = "#{account.label} linked — syncing it in now."
      end
      redirect_to settings_path, notice: notice
    else
      redirect_to settings_path, alert: account.errors.full_messages.to_sentence
    end
  end

  def sync
    account = Current.user.linked_accounts.find(params[:id])
    return redirect_to settings_path, alert: "#{account.label} doesn't sync yet." unless account.syncable?

    SyncLinkedAccountJob.perform_later(account)
    redirect_to settings_path, notice: "Syncing your #{account.label.downcase} now."
  end

  # Scope checkboxes post the ENABLED set; we store the complement so new
  # provider scopes default on for existing links (see LinkedAccount).
  def update
    account = Current.user.linked_accounts.find(params[:id])
    enabled = params.fetch(:enabled_scopes, []).map(&:to_s)
    account.update!(disabled_scopes: account.scopes.keys - enabled)
    redirect_to settings_path, notice: "#{account.label} access updated."
  end

  def destroy
    account = Current.user.linked_accounts.find(params[:id])
    account.destroy!
    redirect_to settings_path, notice: "#{account.label} disconnected and its credentials deleted."
  end

  private
    # Only the fields the provider declares — nothing else lands in the blob.
    def credential_params(settings)
      params.fetch(:credentials, ActionController::Parameters.new)
        .permit(*settings[:fields].map { |field| field[:key] }).to_h
    end
end
