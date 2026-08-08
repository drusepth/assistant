class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  skip_before_action :require_onboarding
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
    # A fresh instance has no one to sign in — onboard the first user instead.
    redirect_to setup_path if User.none?
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      # Unlock rides sign-in (D-vault-crypto): the one moment the app holds
      # the password, so the vault opens without a second prompt.
      unlock_vault_for(user, params[:password])
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    lock_vault
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
