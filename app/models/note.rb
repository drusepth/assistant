class Note < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizeNoteJob

  validates :body, presence: true
end
