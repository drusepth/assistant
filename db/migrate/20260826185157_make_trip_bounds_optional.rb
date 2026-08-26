# A trip born from photos has a box; a trip planned ahead of going doesn't,
# yet (docs/TRIPS_PLAN.md, D-trip-spine). The model enforces all-or-none.
class MakeTripBoundsOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :trips, :south, true
    change_column_null :trips, :west, true
    change_column_null :trips, :north, true
    change_column_null :trips, :east, true
    add_column :trips, :description, :text
  end
end
