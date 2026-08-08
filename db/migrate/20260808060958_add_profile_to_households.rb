# The household profile (D-household-profile): shared facts every member
# pulls from, alongside the D34 `region`. Each column exists because
# something reads it — see the model for the consumer of each.
class AddProfileToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :tagline, :string
    add_column :households, :address, :text
    add_column :households, :phone, :string
    add_column :households, :time_zone, :string
    add_column :households, :home_status, :string
    add_column :households, :moved_in_on, :date
  end
end
