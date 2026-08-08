# Settings › Change password — new with the vault (PASSWORDS_PLAN §4.6):
# until now the only way to change a password was the email-token reset flow,
# which is exactly the flow that can't rewrap a password-derived vault key.
# Knowing the current password (password_challenge) lets the keyring rewrap
# in the same transaction, so the vault never notices.
class UserPasswordsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :update,
    with: -> { redirect_to settings_path, alert: "Try again later." }

  def update
    challenge = params[:password_challenge].to_s

    ApplicationRecord.transaction do
      Current.user.update!(
        password_challenge: challenge,
        password: params[:password],
        password_confirmation: params[:password_confirmation]
      )
      rewrap_keyring(challenge)
    end

    redirect_to settings_path, notice: "Password changed."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to settings_path, alert: error.record.errors.full_messages.to_sentence
  end

  private
    def rewrap_keyring(challenge)
      keyring = Current.user.keyring or return
      vault_key = keyring.unlock(challenge) or return # out-of-sync wrap: recovery is the remaining path

      keyring.rewrap!(vault_key, params[:password])
      grant_vault_key(Current.user, vault_key) if Current.session
    end
end
