# Severity is the one thing about an allergy that changes what anyone does
# about it — a peanut allergy that means an itchy mouth and one that means an
# EpiPen are not the same fact. It rides on notes (docs/HEALTH.md §8) the way
# care_kind rides on events: a narrow column for one structured kind, rather
# than a table for a thing that is still a note.
class AddSeverityToNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :notes, :severity, :string
  end
end
