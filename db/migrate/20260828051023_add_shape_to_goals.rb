class AddShapeToGoals < ActiveRecord::Migration[8.1]
  def change
    add_column :goals, :shape, :string
  end
end
