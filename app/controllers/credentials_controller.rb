# The Passwords vault (D-passwords-vault). Every route lives under
# /credentials so the path-scoped keyring cookie (VaultSession) covers
# exactly this surface. Metadata renders while locked; anything that touches
# a secret requires the unlocked vault key, and secrets only ever leave as
# no-store JSON from #reveal — never rendered into a page body.
class CredentialsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :unlock,
    with: -> { redirect_to credentials_path, alert: "Try again later." }
  rate_limit to: 60, within: 1.minute, only: :reveal,
    with: -> { render json: { error: "slow down" }, status: :too_many_requests }

  before_action :set_own_credential, only: %i[ edit update destroy share unshare ]

  def index
    @keyring = Current.user.keyring
    @kind = params[:kind].presence_in(Credential::KINDS.keys)
    scope = Credential.visible_to(Current.user).includes(:user, :credential_keys)
    scope = scope.where(kind: @kind) if @kind

    # Metadata is AR-encrypted, so search and sort happen in Ruby — a
    # household vault is hundreds of rows, not millions.
    @query = params[:q].to_s.strip
    credentials = scope.to_a
    if @query.present?
      needle = @query.downcase
      credentials.select! do |credential|
        [ credential.name, credential.username, credential.url ].compact.any? { |v| v.downcase.include?(needle) }
      end
    end
    @credentials = credentials.sort_by { |credential| credential.name.downcase }

    @emergency_contacts = Current.user.emergency_contacts.includes(:contact_user)
    @emergency_roles = EmergencyContact.for_contact(Current.user).includes(user: :keyring)
  end

  def show
    @credential = Credential.visible_to(Current.user).find(params[:id])
    @secret_lost = vault_unlocked? && @credential.secret_lost_for?(Current.user)
  end

  def new
    kind = params[:kind].presence_in(Credential::KINDS.keys) || "login"
    @credential = Current.user.credentials.new(kind: kind)
  end

  # Creating needs only the owner's public key (asymmetric wrap), so capture
  # works even while locked — as long as the keyring exists at all.
  def create
    return redirect_to credentials_path, alert: "Sign in again to set up your vault first." if Current.user.keyring.nil?

    @credential = Current.user.credentials.new(credential_params)
    if @credential.valid?
      @credential.write_secrets!(secrets_params)
      redirect_to credential_path(@credential), notice: "#{@credential.name} saved to your vault."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    return redirect_to credential_path(@credential), alert: "Unlock your vault to edit this entry." unless vault_unlocked?

    unless @credential.update(credential_params.except(:kind)) # kind is sealed into the AAD — immutable
      return render :edit, status: :unprocessable_entity
    end

    if @credential.secret_lost_for?(Current.user)
      # The re-enter path (§4.6): fresh item key, wrapped for the owner and
      # any grantees whose rows survived the reset — they read the new value.
      @credential.rotate_secrets!(secrets_params.compact_blank,
        holders: [ Current.user ] + @credential.shared_with)
      redirect_to credential_path(@credential), notice: "#{@credential.name} restored."
    else
      item_key = @credential.unwrap_item_key(Current.user, vault_key)
      return redirect_to credential_path(@credential), alert: "This entry couldn't be opened for editing." if item_key.nil?

      existing = @credential.read_secrets_with_item_key(item_key) || {}
      payload = existing.merge(secrets_params.compact_blank) # blank field = unchanged
      payload.delete("totp") if params[:remove_totp] == "1"
      payload.delete("notes") if params[:remove_notes] == "1"
      @credential.update_secrets!(payload, item_key)
      redirect_to credential_path(@credential), notice: "#{@credential.name} updated."
    end
  end

  def destroy
    @credential.destroy!
    redirect_to credentials_path, notice: "Deleted from your vault."
  end

  # The only way a secret leaves the database: no-store JSON, visibility and
  # decryptability both required, human-paced by the rate limit above.
  def reveal
    credential = Credential.visible_to(Current.user).find(params[:id])
    return render json: { error: "locked" }, status: :unauthorized unless vault_unlocked?

    secrets = credential.read_secrets(Current.user, vault_key)
    return render json: { error: "unavailable" }, status: :unprocessable_entity if secrets.nil?

    response.headers["Cache-Control"] = "no-store"
    body = reveal_body(credential, secrets, params[:field].to_s)
    return head :bad_request if body == :bad_field
    return render json: { error: "empty" }, status: :not_found if body.nil?

    credential.update_column(:last_used_at, Time.current)
    render json: body
  end

  # --- vault lifecycle (collection) ---

  def unlock
    unless Current.user.authenticate(params[:password].to_s)
      return redirect_to credentials_path, alert: "That's not your password."
    end

    if unlock_vault_for(Current.user, params[:password])
      redirect_to credentials_path, notice: "Vault unlocked."
    else
      redirect_to credentials_path,
        alert: "Your vault couldn't be unlocked with that password — if you recently reset it, use your recovery code from the password-reset page."
    end
  end

  def lock
    lock_vault
    redirect_to credentials_path, notice: "Vault locked."
  end

  def recovery
    return redirect_to credentials_path, alert: "Unlock your vault first." unless vault_unlocked?

    @code = Current.user.keyring.generate_recovery!(vault_key)
    response.headers["Cache-Control"] = "no-store"
  end

  def recovery_confirm
    Current.user.keyring&.update!(recovery_confirmed_at: Time.current)
    redirect_to credentials_path, notice: "Recovery kit saved — keep it somewhere that isn't this server."
  end

  # In-request only (PASSWORDS_PLAN §4.7): key material never rides the job
  # queue, so the archive job gets metadata and this button gets the secrets.
  def export
    return redirect_to credentials_path, alert: "Unlock your vault first." unless vault_unlocked?
    unless Current.user.authenticate(params[:password].to_s)
      return redirect_to credentials_path, alert: "Confirm the export with your password."
    end

    response.headers["Cache-Control"] = "no-store"
    send_data Vault::Export.new(Current.user, vault_key).csv,
      filename: "passwords-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  def health
    return redirect_to credentials_path, alert: "Unlock your vault first." unless vault_unlocked?

    @report = Vault::Health.new(Current.user, vault_key).call
    response.headers["Cache-Control"] = "no-store"
  end

  def new_import
  end

  def create_import
    return redirect_to credentials_path, alert: "Sign in again to set up your vault first." if Current.user.keyring.nil?
    return redirect_to import_credentials_path, alert: "Pick a CSV file first." if params[:file].blank?

    result = Vault::Import.new(Current.user, params[:file].read).call
    redirect_to credentials_path,
      notice: "#{result.imported} imported, #{result.skipped} #{"duplicate".pluralize(result.skipped)} skipped."
  rescue Vault::Import::Error => error
    redirect_to import_credentials_path, alert: error.message
  end

  # --- sharing (W3) ---

  def share
    return redirect_to credential_path(@credential), alert: "Unlock your vault to share." unless vault_unlocked?

    grantees = if params[:everyone].present?
      Current.user.household.users.where.not(id: Current.user.id)
    else
      Current.user.household.users.where(id: params[:grantee_id])
    end

    result = Vault::Share.new(@credential, Current.user, vault_key).grant(grantees)
    if result.shared.positive?
      redirect_to credential_path(@credential), notice: "Shared with #{result.names.to_sentence}."
    else
      redirect_to credential_path(@credential), alert: result.error || "Nobody new to share with."
    end
  end

  def unshare
    return redirect_to credential_path(@credential), alert: "Unlock your vault to change sharing." unless vault_unlocked?

    grantee = Current.user.household.users.find(params[:grantee_id])
    if Vault::Share.new(@credential, Current.user, vault_key).revoke(grantee)
      redirect_to credential_path(@credential),
        notice: "Sharing revoked and the entry re-keyed. #{grantee.name} may still remember the password itself — generate a new one if that matters."
    else
      redirect_to credential_path(@credential), alert: "Couldn't revoke — unlock your vault and try again."
    end
  end

  private
    def set_own_credential
      @credential = Current.user.credentials.find(params[:id])
    end

    def credential_params
      params.expect(credential: [ :kind, :name, :username, :url ])
    end

    # Secret fields ride params[:secrets] — the key name matches the
    # :secret filter, so the whole subtree stays out of the logs.
    def secrets_params
      allowed = (@credential || Credential.new(kind: params.dig(:credential, :kind))).secret_field_names
      raw = params.fetch(:secrets, ActionController::Parameters.new).permit(*allowed).to_h
      raw["totp"] = Vault::Crypto.normalize_totp_secret(raw["totp"]) if raw["totp"].present?
      raw
    rescue Vault::Crypto::Error
      raw.except("totp")
    end

    def reveal_body(credential, secrets, field)
      case field
      when "totp"
        seed = secrets["totp"]
        return nil if seed.blank?

        { code: Vault::Crypto.totp_code(seed), seconds_remaining: Vault::Crypto.totp_seconds_remaining }
      when *credential.secret_field_names
        secrets[field].presence && { value: secrets[field] }
      else
        :bad_field
      end
    end
end
