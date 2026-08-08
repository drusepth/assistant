class AddCurrencyToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :currency, :string, null: false, default: "USD"
  end
end
