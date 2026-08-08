class AddRegionToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :region, :string
  end
end
