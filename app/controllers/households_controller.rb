# Household-level facts, admin-edited like the model profile (D15's
# admin split). Today that's `region` (D34, resolving Q12) — the one
# jurisdiction signal every state-sensitive tool shares.
class HouseholdsController < ApplicationController
  def update
    return redirect_to settings_path, alert: "Only household admins can change this." unless Current.user.admin?

    Current.user.household.update!(params.expect(household: [ :region ]))
    redirect_to settings_path, notice: "Household updated."
  end
end
