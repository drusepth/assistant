# Pounds and miles are what the people running this app measure in, so they
# are what the columns hold (D-measurement-units); kilograms and kilometres
# are a display conversion for the user who asks for them. Existing values
# are converted in place, not reinterpreted.
class StoreImperialMeasurements < ActiveRecord::Migration[8.1]
  LB_PER_KG = 2.20462262185
  KM_PER_MI = 1.609344

  def up
    rename_column :pets, :weight_kg, :weight_lb
    execute "UPDATE pets SET weight_lb = ROUND(weight_lb * #{LB_PER_KG}, 2) WHERE weight_lb IS NOT NULL"

    rename_column :places, :radius_km, :radius_mi
    change_column_default :places, :radius_mi, from: 40, to: 25
    execute "UPDATE places SET radius_mi = MAX(3, MIN(190, CAST(ROUND(radius_mi / #{KM_PER_MI}) AS INTEGER)))"

    rename_column :happenings, :distance_km, :distance_mi
    execute "UPDATE happenings SET distance_mi = ROUND(distance_mi / #{KM_PER_MI}, 1) WHERE distance_mi IS NOT NULL"
  end

  def down
    rename_column :pets, :weight_lb, :weight_kg
    execute "UPDATE pets SET weight_kg = ROUND(weight_kg / #{LB_PER_KG}, 2) WHERE weight_kg IS NOT NULL"

    rename_column :places, :radius_mi, :radius_km
    change_column_default :places, :radius_km, from: 25, to: 40
    execute "UPDATE places SET radius_km = CAST(ROUND(radius_km * #{KM_PER_MI}) AS INTEGER)"

    rename_column :happenings, :distance_mi, :distance_km
    execute "UPDATE happenings SET distance_km = ROUND(distance_km * #{KM_PER_MI}, 1) WHERE distance_km IS NOT NULL"
  end
end
