# Fresh-instance onboarding: the very first visit creates the household and
# its admin user in one form. Locked as soon as any user exists — after that,
# the only way in is a session or an invitation link.
class FirstRunController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_onboarding
  before_action :require_fresh_instance

  def new
    @user = User.new
  end

  def create
    household = Household.new(name: household_name)
    @user = household.users.build(user_params.merge(admin: true))

    if household.save
      start_new_session_for(@user)
      unlock_vault_for(@user, user_params[:password])
      redirect_to root_path, notice: "Welcome home, #{@user.name.split.first}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def require_fresh_instance
      redirect_to new_session_path if User.any?
    end

    def user_params
      params.expect(user: [ :name, :email_address, :password ])
    end

    def household_name
      params[:household_name].presence || default_household_name
    end

    def default_household_name
      first_name = params.dig(:user, :name).to_s.split.first
      first_name.present? ? "#{first_name}'s Household" : "Home"
    end
end
