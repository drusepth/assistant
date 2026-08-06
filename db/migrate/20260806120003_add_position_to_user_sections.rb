class AddPositionToUserSections < ActiveRecord::Migration[8.1]
  def change
    add_column :user_sections, :position, :integer
  end
end
