# A lens a record owns says so on the row (D-owned-lens). Until now "is this
# Rex's lens?" was answered by asking the pets table from outside, so every
# surface listing People's children had to remember to ask — and the ones
# that forgot offered the cat as a group.
class AddOwnerTypeToSections < ActiveRecord::Migration[8.1]
  def up
    add_column :sections, :owner_type, :string
    execute <<~SQL
      UPDATE sections SET owner_type = 'Pet'
      WHERE id IN (SELECT section_id FROM pets WHERE section_id IS NOT NULL)
    SQL
  end

  def down
    remove_column :sections, :owner_type
  end
end
