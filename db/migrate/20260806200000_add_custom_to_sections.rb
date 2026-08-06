class AddCustomToSections < ActiveRecord::Migration[8.1]
  def change
    add_column :sections, :custom, :boolean, default: false, null: false
  end
end
