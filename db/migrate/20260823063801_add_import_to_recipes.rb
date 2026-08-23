class AddImportToRecipes < ActiveRecord::Migration[8.1]
  def change
    # Paste-import (RECIPES_PLAN §5.1), on the document-analysis pattern:
    # the row exists from the moment the paste lands, the job fills it in,
    # and a failure is visible with a retry rather than silent.
    add_column :recipes, :import_status, :string
    add_column :recipes, :import_error, :string
    # The text the import read, kept so a failed run can be retried without
    # asking the user to find the page again.
    add_column :recipes, :import_source, :text
  end
end
