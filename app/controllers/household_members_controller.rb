class HouseholdMembersController < ApplicationController
  before_action :require_admin
  before_action :set_member
  before_action :forbid_acting_on_self

  # Toggle the admin role.
  def update
    @member.update!(admin: ActiveModel::Type::Boolean.new.cast(params[:admin]))
    redirect_to settings_path, notice: "#{@member.name} is #{@member.admin? ? "now" : "no longer"} an admin."
  end

  def destroy
    @member.destroy!
    redirect_to settings_path, notice: "#{@member.name} was removed, along with all of their data."
  end

  # A password reset link for a member who is locked out (D-instance-mail).
  # Most instances send no mail, so the admin hands this over the way they
  # hand over invitations. Rendered straight from the POST rather than
  # redirected, so the token never sits in a flash cookie or a GET URL in
  # the admin's history.
  #
  # What it can't reach: the member's password vault and diary stay sealed
  # unless they have their recovery code (D-vault-crypto), whoever uses it.
  # What it can: the rest of their account. That is the same trust an admin
  # already holds by being able to delete the account outright, and it is
  # logged like the household reset is.
  def reset_link
    Rails.logger.warn(
      "Password reset link issued for #{@member.email_address} (##{@member.id}) by #{Current.user.email_address}"
    )
    @reset_url = edit_password_url(@member.handed_password_reset_token)
  end

  private
    def set_member
      @member = Current.user.household.users.find(params[:id])
    end

    def forbid_acting_on_self
      redirect_to settings_path, alert: "You can't change your own membership." if @member == Current.user
    end
end
