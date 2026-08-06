class AddAnalysisToDocuments < ActiveRecord::Migration[8.1]
  def change
    change_table :documents do |t|
      t.string :analysis_status
      t.string :analysis_error
      t.json :suggested_sections, default: []
    end
  end
end
