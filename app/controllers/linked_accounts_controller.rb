# Connect/disconnect outside services and tune what each one shares (D26).
# Strictly per-user: links belong to whoever created them, and scope edits
# only ever touch Current.user's own rows.
class LinkedAccountsController < ApplicationController
  def create
    provider = params[:provider].to_s
    settings = LinkedAccount::PROVIDERS[provider]
    return redirect_to settings_path, alert: "Unknown service." unless settings

    account = Current.user.linked_accounts.build(
      provider: provider, credentials: credential_params(settings), label: params[:label].presence)
    if account.save
      notice = "#{account.display_name} linked. The assistant has full access — adjust what it can use below."
      if account.syncable?
        SyncLinkedAccountJob.perform_later(account)
        notice = "#{account.display_name} linked — syncing it in now."
      end
      redirect_to settings_path, notice: notice
    else
      redirect_to settings_path, alert: account.errors.full_messages.to_sentence
    end
  end

  def sync
    account = Current.user.linked_accounts.find(params[:id])
    return redirect_to settings_path, alert: "#{account.display_name} doesn't sync yet." unless account.syncable?

    SyncLinkedAccountJob.perform_later(account)
    redirect_to settings_path, notice: "Syncing #{account.display_name} now."
  end

  # Scope checkboxes post the ENABLED set; we store the complement so new
  # provider scopes default on for existing links (see LinkedAccount).
  def update
    account = Current.user.linked_accounts.find(params[:id])
    enabled = params.fetch(:enabled_scopes, []).map(&:to_s)
    account.update!(disabled_scopes: account.scopes.keys - enabled)
    redirect_to settings_path, notice: "#{account.display_name} access updated."
  end

  def destroy
    account = Current.user.linked_accounts.find(params[:id])
    account.destroy!
    redirect_to settings_path, notice: "#{account.display_name} disconnected and its credentials deleted."
  end

  # Per-link dials (EMAIL_PLAN.md §3/§7): digest inclusion, urgent alerts,
  # AI processing, contact recency, mirror window, own addresses, pause —
  # sparse-stored so defaults can evolve (E0's settings convention).
  SETTING_SWITCHES = %w[ paused alerts contact_recency ].freeze # default off
  SETTING_HOLDS = %w[ digest ai_processing ].freeze             # default on

  def update_settings
    account = Current.user.linked_accounts.find(params[:id])
    settings = account.settings.dup

    SETTING_SWITCHES.each { |key| settings[key] = params[key] == "1" }
    SETTING_HOLDS.each { |key| settings[key] = params[key] == "1" }
    if params.key?(:mirror_window_days)
      settings["mirror_window_days"] = params[:mirror_window_days].to_i.clamp(0, 3650)
    end
    if params.key?(:own_addresses)
      settings["own_addresses"] = params[:own_addresses].to_s.split(/[\s,;]+/).map(&:downcase).uniq.reject(&:blank?)
    end

    account.update!(settings: settings)
    redirect_to settings_path, notice: "#{account.display_name} settings saved."
  end

  private
    # Only the fields the provider declares — nothing else lands in the blob.
    def credential_params(settings)
      params.fetch(:credentials, ActionController::Parameters.new)
        .permit(*settings[:fields].map { |field| field[:key] }).to_h
    end
end
