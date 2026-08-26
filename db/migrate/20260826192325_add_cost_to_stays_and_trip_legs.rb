# What a booking costs (D-trip-costs): a fact about the reservation, like
# its confirmation code — not a Money primitive. Integer cents, per the
# house rule: no floats anywhere in money math.
class AddCostToStaysAndTripLegs < ActiveRecord::Migration[8.1]
  def change
    add_column :stays, :cost_cents, :integer
    add_column :trip_legs, :cost_cents, :integer
  end
end
