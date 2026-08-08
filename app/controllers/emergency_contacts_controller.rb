# Emergency access (PASSWORDS_PLAN §7). Routes live under /credentials so
# the keyring cookie travels: setup wraps the owner's vault key (owner must
# be unlocked), and reading through a released escrow needs the contact's own
# unlocked vault to unwrap the chain. The wait is app-enforced policy — the
# setup copy says so in the view.
class EmergencyContactsController < ApplicationController
  before_action :set_own_contact, only: %i[ destroy deny ]
  before_action :set_contact_role, only: %i[ request_access access emergency_reveal ]

  rate_limit to: 60, within: 1.minute, only: :emergency_reveal,
    with: -> { render json: { error: "slow down" }, status: :too_many_requests }

  def create
    return redirect_to credentials_path, alert: "Unlock your vault first." unless vault_unlocked?

    contact = Current.user.household.users.where.not(id: Current.user.id).find_by(id: params[:contact_user_id])
    return redirect_to credentials_path, alert: "Pick a household member." if contact.nil?
    return redirect_to credentials_path, alert: "#{contact.name} needs to sign in once before they can be your emergency contact." if contact.keyring.nil?

    record = EmergencyContact.escrow!(owner: Current.user, contact: contact,
      vault_key: vault_key, wait_days: params.fetch(:wait_days, 7).to_i.clamp(1, 90))
    VaultEvent.record("emergency_added", user: Current.user, actor: Current.user, subject_user: contact)
    redirect_to credentials_path,
      notice: "#{record.contact_user.name} can now request emergency access — you'll have #{record.wait_days} days to deny."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to credentials_path, alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    @contact.destroy!
    VaultEvent.record("emergency_revoked", user: Current.user, actor: Current.user,
      subject_user: @contact.contact_user)
    redirect_to credentials_path, notice: "Emergency access revoked."
  end

  # Contact side: start the clock, tell the owner everywhere we can.
  def request_access
    return redirect_to credentials_path, alert: "Already requested." if @role.requested?

    @role.update!(requested_at: Time.current)
    VaultEvent.record("emergency_requested", user: @role.user, actor: Current.user, subject_user: Current.user)
    notify(@role.user,
      "#{Current.user.name} requested emergency access to your password vault — deny within #{@role.wait_days} days if this is wrong")
    redirect_to credentials_path,
      notice: "Requested. Unless #{@role.user.name} denies it, access opens in #{@role.wait_days} days."
  end

  # Owner side: one click, request gone.
  def deny
    @contact.update!(requested_at: nil, released_at: nil)
    VaultEvent.record("emergency_denied", user: Current.user, actor: Current.user,
      subject_user: @contact.contact_user)
    notify(@contact.contact_user, "#{Current.user.name} denied your emergency vault access request")
    redirect_to credentials_path, notice: "Denied — the request is cleared."
  end

  # Read-only view of the owner's vault once the wait has elapsed.
  def access
    return redirect_to credentials_path, alert: "Unlock your own vault first." unless vault_unlocked?
    return redirect_to credentials_path, alert: "The waiting period hasn't elapsed." unless @role.releasable?

    if @role.released_at.nil?
      @role.update!(released_at: Time.current)
      VaultEvent.record("emergency_opened", user: @role.user, actor: Current.user, subject_user: Current.user)
      notify(@role.user, "#{Current.user.name} opened emergency access to your password vault")
    end

    @owner = @role.user
    @credentials = @owner.credentials.order(:created_at).sort_by { |c| c.name.downcase }
    response.headers["Cache-Control"] = "no-store"
  end

  def emergency_reveal
    return render json: { error: "locked" }, status: :unauthorized unless vault_unlocked?
    return render json: { error: "not released" }, status: :forbidden unless @role.releasable? && @role.released_at

    owner_vault_key = @role.owner_vault_key(vault_key)
    return render json: { error: "unavailable" }, status: :unprocessable_entity if owner_vault_key.nil?

    credential = @role.user.credentials.find(params[:credential_id])
    secrets = credential.read_secrets(@role.user, owner_vault_key)
    return render json: { error: "unavailable" }, status: :unprocessable_entity if secrets.nil?

    response.headers["Cache-Control"] = "no-store"
    field = params[:field].to_s
    return head :bad_request unless field == "totp" || credential.secret_field_names.include?(field)

    value = field == "totp" ? secrets["totp"] && Vault::Crypto.totp_code(secrets["totp"]) : secrets[field]
    return render json: { error: "empty" }, status: :not_found if value.blank?

    render json: { value: value }
  end

  private
    def set_own_contact
      @contact = Current.user.emergency_contacts.find(params[:id])
    end

    def set_contact_role
      @role = EmergencyContact.for_contact(Current.user).find(params[:id])
    end

    def notify(user, title)
      Notifications::Deliver.new(user, titles: [ title ], summary: title).call
    end
end
