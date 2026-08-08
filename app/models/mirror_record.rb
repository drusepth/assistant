# Base class for the mirror database (D32): per-source caches of outside
# services — owner-private, derived, re-syncable. Mirror models never
# include Visible or Sectionable (there is deliberately no path from a
# grant to a mirror row), and references to primary-database records are
# soft ids resolved in Ruby — no cross-database foreign keys or joins.
class MirrorRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :mirror }
end
