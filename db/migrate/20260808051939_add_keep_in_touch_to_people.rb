class AddKeepInTouchToPeople < ActiveRecord::Migration[8.1]
  def up
    add_column :people, :keep_in_touch, :boolean, default: false, null: false
    # Logging contact was the opt-in until the circle flag existed (Q8), so
    # the flag inherits it — nobody's stay-in-touch nudges change on upgrade.
    execute "UPDATE people SET keep_in_touch = TRUE WHERE last_contacted_on IS NOT NULL"
  end

  def down
    remove_column :people, :keep_in_touch
  end
end
