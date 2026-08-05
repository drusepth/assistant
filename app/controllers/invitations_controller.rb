class InvitationsController < ApplicationController
  allow_unauthenticated_access only: %i[ show accept ]
  before_action :require_admin, only: %i[ create destroy ]
  before_action :redirect_signed_in_users, only: %i[ show accept ]
  before_action :set_invitation, only: %i[ show accept ]
  rate_limit to: 10, within: 3.minutes, only: :accept,
    with: -> { redirect_to new_session_url, alert: "Try again later." }

  def create
    invitation = Current.user.household.invitations.new(invitation_params.merge(inviter: Current.user))
    if invitation.save
      redirect_to settings_path, notice: "Invite link created for #{invitation.name} — copy it below."
    else
      redirect_to settings_path, alert: invitation.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.household.invitations.pending.find(params[:id]).destroy!
    redirect_to settings_path, notice: "Invitation revoked."
  end

  # The join page, reached via a copied link.
  def show
    @user = User.new(name: @invitation.name)
  end

  def accept
    @user = @invitation.household.users.build(user_params)
    if @user.save
      @invitation.update!(accepted_at: Time.current)
      start_new_session_for(@user)
      redirect_to root_path, notice: "Welcome to #{@invitation.household.name}, #{@user.name.split.first}!"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def set_invitation
      @invitation = Invitation.find_by_token_for(:acceptance, params[:token])
      return if @invitation.present? && !@invitation.accepted?

      redirect_to new_session_path, alert: "That invite link is no longer valid — ask for a new one."
    end

    def redirect_signed_in_users
      redirect_to root_path, alert: "You're already signed in." if authenticated?
    end

    def invitation_params
      params.expect(invitation: [ :name ])
    end

    def user_params
      params.expect(user: [ :name, :email_address, :password ])
    end
end
