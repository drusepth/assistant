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

  private
    def set_member
      @member = Current.user.household.users.find(params[:id])
    end

    def forbid_acting_on_self
      redirect_to settings_path, alert: "You can't change your own membership." if @member == Current.user
    end
end
