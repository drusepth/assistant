class AddRadarBriefsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :radar_brief, :text
    add_column :users, :causes_brief, :text
  end
end
