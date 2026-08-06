class Goal < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizeGoalJob

  has_many :tasks, dependent: :nullify
  has_many :events, dependent: :nullify

  enum :status, { backlog: 0, active: 1, done: 2 }, default: :backlog

  validates :title, presence: true
end
