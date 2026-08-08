class AddHealthPlanToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :health_plan, :boolean
  end
end
