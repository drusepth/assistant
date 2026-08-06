class Task < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizeTaskJob

  belongs_to :goal, optional: true

  # Which board column an open task sits in. Done isn't a bucket — it stays
  # derived from completed_at so completing from any view lands the task in
  # the Done column without a second state to keep in sync.
  enum :bucket, { later: 0, today: 1 }, default: :later

  validates :title, presence: true

  scope :open, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :due_by, ->(date) { where(due_on: ..date) }

  def completed? = completed_at.present?

  # The Today column is bucket ∪ due date: pulled in by hand (or scheduled by
  # a goal breakdown), or surfaced automatically once its due date arrives.
  def for_today? = today? || (due_on.present? && due_on <= Date.current)

  def complete!
    update!(completed_at: Time.current)
    goal&.finish_if_done!
  end

  def reopen!
    update!(completed_at: nil)
    goal&.reactivate!
  end
end
