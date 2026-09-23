class PasswordsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_onboarding
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  # Without instance mail (D-instance-mail) there is nothing to send, so the
  # form isn't offered and a stray POST says so instead of claiming success.
  def create
    unless InstanceMail.password_resets?
      return redirect_to new_password_path,
        alert: "This server doesn't send email. Ask a household admin for a reset link."
    end

    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    # A reset can't rewrap the vault (no old password), so the keyring needs
    # the recovery code — or an explicit, knowing forfeit (D-vault-crypto).
    if needs_recovery_decision? && !recovery_code_valid? && params[:forfeit_vault] != "1"
      return redirect_to edit_password_path(params[:token]),
        alert: "That recovery code didn't match. Enter the code from your recovery kit, or confirm you're giving up your saved passwords."
    end

    if @user.update(params.permit(:password, :password_confirmation))
      carry_keyring_through_reset
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "Password has been reset."
    else
      redirect_to edit_password_path(params[:token]), alert: "Passwords did not match."
    end
  end

  private
    # Emailed links and handed-over links (an admin's, or the operator's
    # rake task) open the same form.
    def set_user_by_token
      @user = User.find_by_any_password_reset_token(params[:token])
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired." unless @user
    end

    def needs_recovery_decision?
      @user.keyring&.recovery_wrapped_key.present?
    end

    def recovery_code_valid?
      return false if params[:recovery_code].blank?

      @recovered_vault_key ||= @user.keyring.unlock_with_recovery(params[:recovery_code])
      @recovered_vault_key.present?
    end

    def carry_keyring_through_reset
      keyring = @user.keyring or return

      if needs_recovery_decision? && recovery_code_valid?
        # Same vault key, new wrap; the used recovery wrap is cleared so the
        # next unlocked visit prompts for a fresh kit.
        keyring.rewrap!(@recovered_vault_key, params[:password])
        keyring.update!(recovery_salt: nil, recovery_wrapped_key: nil, recovery_confirmed_at: nil)
      else
        # No recovery wrap on file, or an explicit forfeit: fresh keys, own
        # key rows deleted (secrets show as lost), escrow rows die too.
        keyring.reset!(params[:password])
      end
    end
end
