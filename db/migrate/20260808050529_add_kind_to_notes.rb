class AddKindToNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :notes, :kind, :string
  end
end
