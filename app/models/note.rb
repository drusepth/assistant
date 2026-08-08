class Note < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizeNoteJob

  # A structured flavor of note (nil = plain). "medication" is the first
  # (docs/HEALTH.md §7): the med list is notes, so it exports, shares, and
  # feeds tool context like everything else.
  MEDICATION = "medication".freeze
  scope :medications, -> { where(kind: MEDICATION) }

  validates :body, presence: true

  def medication? = kind == MEDICATION
end
