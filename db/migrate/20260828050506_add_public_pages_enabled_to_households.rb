class AddPublicPagesEnabledToHouseholds < ActiveRecord::Migration[8.1]
  # The /about switch (D-about-pages). Default on: the pages are identical
  # on every install, so there is nothing about this household to broadcast,
  # and a self-hoster who never finds the switch still gets the docs.
  def change
    add_column :households, :public_pages_enabled, :boolean, default: true, null: false
  end
end
