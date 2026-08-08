class AddCareKindToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :care_kind, :string
  end
end
