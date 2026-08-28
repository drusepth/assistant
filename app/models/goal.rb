class Goal < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = BreakDownGoalJob

  has_many :tasks, dependent: :nullify
  has_many :events, dependent: :nullify
  # A curriculum topic can point at the goal it's being learned for
  # (D-education-spine). Same posture as tasks and events: dropping the goal
  # drops the link, never the learning — and without this the foreign key
  # made the goal undeletable.
  has_many :topics, dependent: :nullify

  # paused (D-goal-pause): shelved without shame — off the board's strip,
  # parked on the Goals tab, one click each way.
  enum :status, { active: 1, done: 2, paused: 3 }, default: :active

  # shape (D-goal-shape): set once by the breakdown call, never reclassified.
  # finite goals show percent; ongoing ones show momentum; nil (hand-created,
  # no model) falls back to percent.
  SHAPES = %w[ finite ongoing ].freeze

  # An active goal nobody has touched in this long says so, gently, and sorts
  # into the strip's attention band (D-goal-pause).
  STALE_AFTER = 6.weeks

  validates :title, presence: true
  validates :shape, inclusion: { in: SHAPES }, allow_nil: true

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

  def pause!
    update!(status: :paused) if active?
  end

  def resume!
    update!(status: :active) if paused?
  end

  def ongoing_shape? = shape == "ongoing"

  # Enumerable on purpose: the strip and Goals tab preload :tasks, so these
  # stay query-free per goal.
  def open_steps = tasks.reject(&:completed?)

  def last_progress_at = tasks.filter_map(&:completed_at).max

  def steps_this_week = tasks.count { |task| task.completed_at && task.completed_at >= 1.week.ago }

  # Movement of any kind — a step done, a plan made, or just being new.
  def last_activity_at
    [ last_progress_at, broken_down_at, created_at ].compact.max
  end

  def stale? = active? && last_activity_at < STALE_AFTER.ago

  # No open step will ever surface itself on the board: nothing pulled into
  # Today, nothing dated (D17's Today logic never resurfaces an undated
  # later-bucket task), or no steps at all. Adrift goals get the strip's
  # "no next step" flag so they can't silently exit daily life.
  def adrift?
    active? && !breaking_down? &&
      open_steps.none? { |task| task.for_today? || task.due_on.present? }
  end

  # Strip order (D-tasks-two-surfaces): working-on-now first, then goals that
  # need a decision, then the rest by recency — deterministic Ruby over a
  # handful of rows, never created_at, never a model call.
  def self.by_attention(goals)
    goals.sort_by { |goal| [ goal.attention_band, -goal.last_activity_at.to_i, goal.id ] }
  end

  def attention_band
    if open_steps.any?(&:for_today?) then 0
    elsif adrift? || stale? then 1
    else 2
    end
  end
end
