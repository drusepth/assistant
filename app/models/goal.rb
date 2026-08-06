class Goal < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = BreakDownGoalJob

  has_many :tasks, dependent: :nullify
  has_many :events, dependent: :nullify

  enum :status, { active: 1, done: 2 }, default: :active

  validates :title, presence: true

  # A new goal is handed to the household's model to be broken into day-sized
  # tasks (which also files it into sections) — the user only names the outcome.
  def enqueue_break_down!
    BreakDownGoalJob.perform_later(self) if auto_sort_profile
  end

  # True between creation and the breakdown job's first attempt (the job
  # stamps broken_down_at even on failure, so this can't stick forever).
  def breaking_down? = broken_down_at.nil? && auto_sort_profile.present?

  def finish_if_done!
    update!(status: :done) if active? && tasks.open.none?
  end

  def reactivate!
    update!(status: :active) if done?
  end
end
