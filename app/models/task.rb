class Task < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizeTaskJob

  belongs_to :goal, optional: true
  # The task's conversation (D30): a task_chat run bound here via the
  # polymorphic subject. A conversation without its task is meaningless.
  has_many :tool_runs, as: :subject, dependent: :destroy

  # Which board column an open task sits in. Done isn't a bucket — it stays
  # derived from completed_at so completing from any view lands the task in
  # the Done column without a second state to keep in sync.
  enum :bucket, { later: 0, today: 1 }, default: :later

  validates :title, presence: true

  scope :open, -> { where(completed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :due_by, ->(date) { where(due_on: ..date) }

  def completed? = completed_at.present?

  # The opener a task without capture-time questions falls back to, so the
  # conversation works on every task — hand-tagged, imported, or pre-D30.
  FALLBACK_OPENER = "Want to work through this together? Tell me where you're at with it — or what's making it tricky — and we'll take it from there.".freeze

  def conversation
    tool_runs.where(tool_slug: "task_chat").order(:created_at, :id).last
  end

  # What the assistant opens the conversation with (D30): the questions the
  # capture-time model call stored, shown with zero further LLM spend.
  def conversation_openers
    stored = Array(guiding_questions).grep(String).map(&:strip).reject(&:empty?)
    stored.presence || [ FALLBACK_OPENER ]
  end

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
