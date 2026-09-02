class CreateDocumentItems < ActiveRecord::Migration[8.1]
  def change
    # Provenance (D-document-intake): which rows a document produced, the
    # tool_run_items shape. Deleting the document deletes these and nothing
    # else — the visit happened whether or not you keep the scan.
    create_table :document_items do |t|
      t.references :document, null: false, foreign_key: true
      t.references :item, polymorphic: true, null: false
      t.string :fingerprint, null: false

      t.timestamps
    end
  end
end
