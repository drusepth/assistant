class AddMeasurementSystemToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :measurement_system, :string, default: "imperial", null: false
  end
end
