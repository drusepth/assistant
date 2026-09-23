class Task < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable
  include Remindable

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
  validate :routine_is_valid
  after_save :save_routine

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

  # A due date is a day, not a moment, so a relative reminder counts back
  # from the start of that day. An undated task can still carry an
  # absolute reminder — there is just nothing to count back from.
  def remind_from
    due_on&.in_time_zone(user.household.zone)&.change(hour: Remindable::DAY_START_HOUR)
  end

  # Finishing a task retires the one-shot reminders about it — a ping about
  # something already done reads as the app not noticing. A standing
  # reminder stays: "take the trash out" checked off this week is the chore
  # done once, not the chore over (D-standing-reminders).
  def complete!
    update!(completed_at: Time.current)
    reminders.pending.where(rule: nil).destroy_all
    goal&.finish_if_done!
  end

  def reopen!
    update!(completed_at: nil)
    goal&.reactivate!
  end

  # A routine (D-task-routines): the chore's standing reminder, and the one
  # the task form's Repeat picker reads and writes. Other reminders on the
  # task — set from its Reminders card — are left alone.
  def routine
    return @routine_draft if defined?(@routine_draft)

    reminders.standing.pending.order(:id).first
  end

  def routine? = routine.present?

  # The form's Repeat fields. "Doesn't repeat" retires the routine; anything
  # else composes one through the Reminder's own picker attributes, so the
  # rule, the start day and the time mean exactly what they do on a
  # reminder. Its words are always the task's title.
  def routine_attributes=(attributes)
    attributes = attributes.to_h.symbolize_keys.slice(:repeat, :deliver_on, :deliver_time, :repeat_days, :repeat_until)
    current = reminders.standing.pending.order(:id).first

    if attributes[:repeat].blank? || attributes[:repeat] == "none"
      @routine_retired = current
      @routine_draft = nil
    else
      attributes[:repeat_until] = attributes[:repeat_until].presence
      attributes[:deliver_on] = attributes[:deliver_on].presence || Date.current
      @routine_draft = current || Reminder.new
      @routine_draft.assign_attributes(attributes)
    end
  end

  # What a routine firing does to the board (Q-routines, D-task-routines):
  # the same row comes back — reopened if it was done, pulled into Today
  # either way. One durable task, never a row per occurrence.
  def come_round!
    was_done = completed?
    update!(completed_at: nil, bucket: :today)
    goal&.reactivate! if was_done
  end

  private
    def routine_is_valid
      return unless @routine_draft

      @routine_draft.assign_attributes(user: user, subject: self, body: title.to_s.truncate(Reminder::MAX_BODY))
      return if @routine_draft.valid?

      @routine_draft.errors.full_messages.each { |message| errors.add(:base, message) }
    end

    def save_routine
      @routine_retired&.destroy!
      @routine_draft&.save!
      remove_instance_variable(:@routine_draft) if defined?(@routine_draft)
      @routine_retired = nil
    end
end
