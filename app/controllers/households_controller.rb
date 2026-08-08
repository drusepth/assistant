# The household profile page (D-household-profile): the shared facts every
# member's assistant pulls from — where you live, how to reach the house,
# who lives here — plus member management and invitations, which moved here
# off the personal Settings page.
#
# Editing is admin-only (the D15 admin split); everyone else reads. `region`
# (D34) keeps its meaning and its tool consumers, it just lives here now.
class HouseholdsController < ApplicationController
  before_action :require_household_admin, only: %i[ update destroy_banner ]

  def show
    @household = Current.user.household
    @members = @household.users.order(:name)
    @pending_invitations = @household.invitations.pending.order(:created_at) if Current.user.admin?
  end

  def update
    if Current.user.household.update(household_params)
      redirect_to household_path, notice: "Household updated."
    else
      @household = Current.user.household
      @members = @household.users.order(:name)
      @pending_invitations = @household.invitations.pending.order(:created_at)
      render :show, status: :unprocessable_entity
    end
  end

  def destroy_banner
    Current.user.household.banner.purge_later
    redirect_to household_path, notice: "Banner removed."
  end

  private
    def household_params
      params.expect(household: [ :name, :tagline, :region, :address, :phone, :time_zone,
        :currency, :home_status, :moved_in_on, :banner ])
    end

    # Same guard as require_admin, but bounced back to the household page —
    # a member who lands here should stay here.
    def require_household_admin
      redirect_to household_path, alert: "Only household admins can change this." unless Current.user.admin?
    end
end
