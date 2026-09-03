class AddLandingsToDocuments < ActiveRecord::Migration[8.1]
  def change
    # What a document proposes (D-document-intake): one entry per landing
    # — kind, validated attributes, fingerprint, and a status of proposed /
    # saved / skipped. The review page reads and the Save click updates.
    add_column :documents, :landings, :json, default: [], null: false
  end
end
