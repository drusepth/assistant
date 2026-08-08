# Household-level settings (email plan E0): the clock every scheduled
# thing reads, and the optional Q12 region hint. Admins manage the
# household (D15), so only they may set these.
class HouseholdsController < ApplicationController
  def update
    return redirect_to settings_path, alert: "Only household admins can change household settings." unless Current.user.admin?

    household = Current.user.household
    if household.update(params.expect(household: %i[ time_zone region ]))
      redirect_to settings_path, notice: "Household settings updated."
    else
      redirect_to settings_path, alert: household.errors.full_messages.to_sentence
    end
  end
end
