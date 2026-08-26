class AddPackageUnitToPetFoods < ActiveRecord::Migration[8.1]
  # A bag is sold in kilos and fed in grams, so one shared unit column made
  # the owner do the conversion — and getting it wrong produced a confident
  # "runs out today" rather than an error (D-pet-food-shelf).
  def change
    add_column :pet_foods, :package_unit, :string, null: false, default: "g"
    up_only { execute "UPDATE pet_foods SET package_unit = unit" }
  end
end
