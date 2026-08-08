class AddExtractedFactsToDocuments < ActiveRecord::Migration[8.1]
  def change
    # Structured facts document analysis pulls out alongside the summary —
    # today the "pay_stub" family (docs/CAREER.md §1, D-career-signal); other document
    # kinds can add their own keys without another migration.
    add_column :documents, :extracted_facts, :json, default: {}, null: false
  end
end
