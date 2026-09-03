# Joins a document to the rows it produced (D-document-intake) — the
# tool_run_items shape, read both ways: the document page lists what was
# saved from it, and a row can say "from the vet report of 12 Aug". Rows
# outlive the join: deleting the scan does not delete the visit.
class DocumentItem < ApplicationRecord
  belongs_to :document
  belongs_to :item, polymorphic: true

  # The document a row came from, if any — the provenance line's source.
  def self.source_for(item)
    where(item: item).includes(:document).order(:id).first&.document
  end
end
