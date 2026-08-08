# Household-level facts, admin-edited like the model profile (D15's
# admin split): `region` (D34, resolving Q12) — the one jurisdiction
# signal every state-sensitive tool shares — and `time_zone`, the clock
# everything scheduled reads (the mail digest's "8am" means 8am here).
class HouseholdsController < ApplicationController
  def update
    return redirect_to settings_path, alert: "Only household admins can change this." unless Current.user.admin?

    household = Current.user.household
    if household.update(params.expect(household: %i[ region time_zone ]))
      redirect_to settings_path, notice: "Household updated."
    else
      redirect_to settings_path, alert: household.errors.full_messages.to_sentence
    end
  end
end
