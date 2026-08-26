# notes.kind was the one flavor column in the schema where NULL meant "the
# plain one" — every other (credentials.kind "login", feeds.kind "rss",
# spending_accounts.kind "checking", suggestions.kind "nudge", …) is NOT NULL
# and names its plain case. That gap is not cosmetic: `kind != 'allergy'` is
# NULL, not true, for a NULL kind, so any negated query silently drops every
# plain note — which is exactly what emptied the doctor-visit-prep notes block
# (D-allergy-notes). Naming the plain case removes the trap at the source
# instead of asking each call site to remember the NULL arm.
class BackfillNotesKindDefault < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE notes SET kind = 'plain' WHERE kind IS NULL"
    change_column_default :notes, :kind, "plain"
    change_column_null :notes, :kind, false
  end

  def down
    change_column_null :notes, :kind, true
    change_column_default :notes, :kind, nil
    execute "UPDATE notes SET kind = NULL WHERE kind = 'plain'"
  end
end
