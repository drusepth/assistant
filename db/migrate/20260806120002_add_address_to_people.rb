class AddAddressToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :address, :text
  end
end
