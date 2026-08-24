# A real Day One export is thousands of entries, and importing it is
# thousands of seals plus thousands of inserts — far past what one request
# should hold. The usual answer, a background job, is exactly what this
# container may not use: key material never rides the queue.
#
# So the work is staged instead, and the staging is itself sealed. A
# plaintext tempfile would have been the easy way and would have put a
# person's whole diary on disk in the clear — the one thing this feature
# exists to prevent.
class CreateDiaryImports < ActiveRecord::Migration[8.1]
  def change
    create_table :diary_imports do |t|
      t.references :user, null: false, foreign_key: true

      # The parsed, deduplicated entries still to be written, sealed under
      # the user's diary key.
      t.binary :payload_ciphertext, null: false

      t.integer :total, null: false, default: 0
      t.integer :cursor, null: false, default: 0
      t.integer :imported, null: false, default: 0
      t.integer :skipped, null: false, default: 0
      t.string :source_label

      t.timestamps
    end
  end
end
