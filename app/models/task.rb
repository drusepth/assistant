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
  has_one :schedule_reminder, -> { where(schedule: true) }, class_name: "Reminder", as: :subject

  before_validation :compose_repeat_rule
  before_validation :default_schedule_day
  validate :repeat_rule_is_usable
  validate :reminder_time_is_ahead
  after_save :sync_schedule_reminder

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
    stored_questions.presence || [ FALLBACK_OPENER ]
  end

  # Whether this task is thinking work — decide, draft, plan — rather than an
  # errand like "Buy batteries" (D-task-answer-shape). The model has already
  # answered that at capture: it writes opening questions only for mental work
  # and leaves them empty for errands. Empty also means "never asked" (made by
  # hand, imported, pre-D30, no model configured), and that is fine: the page
  # treats both the same way, folding the answer card and the conversation
  # down to one line each, so the ambiguity can't show the wrong thing.
  def mental_work? = stored_questions.any?

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
    reminders.by_hand.pending.where(rule: nil).destroy_all
    goal&.finish_if_done!
  end

  def reopen!
    update!(completed_at: nil)
    goal&.reactivate!
  end

  # The task's schedule (D-reminders-on-tasks) is the task's own: a due
  # day, an optional `repeat_rule` (RRULE text), and an optional
  # `remind_time` ("16:00"). Underneath sits one reminder row, marked
  # `schedule`, that the task keeps in step with those three — the user
  # never manages it, and nothing has to guess which reminder it is.
  #
  # A repeating task is a routine (D-task-routines): its schedule reminder
  # repeats, and each firing brings the task back onto the board. With no
  # time picked it fires silently — the chore comes round without a ping.
  def routine? = repeat_rule.present?

  def recurrence = Recurrence::Rule.parse(repeat_rule)

  # Reminders set by hand from the task page, beside the schedule.
  def extra_reminders = reminders.by_hand.pending.order(:deliver_at)

  # The Repeat picker's parts: a Reminder::REPEAT_OPTIONS key, the weekday
  # chips, and an optional last day. Each reads back from the stored rule,
  # so an edit opens on what was chosen; anything assigned from the form
  # wins, and is composed into `repeat_rule` before validation.
  def repeat = @picked&.key?(:repeat) ? @picked[:repeat] : (Reminder.repeat_key_for(recurrence) || "none")
  def repeat_days = @picked&.key?(:days) ? @picked[:days] : (recurrence&.weekdays || [])
  def repeat_until = @picked&.key?(:until) ? @picked[:until] : recurrence&.until_date

  def repeat=(key)
    pick(:repeat, key.presence || "none")
  end

  def repeat_days=(codes)
    pick(:days, Array(codes).compact_blank)
  end

  def repeat_until=(date)
    pick(:until, date.is_a?(Date) ? date : (Date.iso8601(date.to_s) if date.present?))
  rescue Date::Error
    pick(:until, nil)
  end

  def remind_time=(value)
    @time_picked = true
    super(value.presence)
  end

  # What a routine firing does to the board (Q-routines, D-task-routines):
  # the same row comes back — reopened if it was done, due on the day it
  # came round, pulled into Today. One durable task, never a row per
  # occurrence.
  def come_round!(on: Date.current)
    was_done = completed?
    # The dispatcher has already moved the series on; this is the board
    # catching up, not the schedule changing.
    @coming_round = true
    update!(completed_at: nil, bucket: :today, due_on: on)
    goal&.reactivate! if was_done
  ensure
    @coming_round = false
  end

  private
    def stored_questions
      Array(guiding_questions).grep(String).map(&:strip).reject(&:empty?)
    end

    def zone = user.household.zone

    def pick(part, value)
      (@picked ||= {})[part] = value
    end

    def compose_repeat_rule
      return unless @picked

      self.repeat_rule = Reminder.compose_rule(repeat, days: repeat_days, on: due_on || Date.current, until_date: repeat_until)
    end

    # A repeat or a reminder time needs a day to start from; with none
    # picked, that day is today.
    def default_schedule_day
      self.due_on ||= Date.current if repeat_rule.present? || remind_time.present?
    end

    def repeat_rule_is_usable
      return if repeat_rule.blank?

      rule = recurrence
      if !rule&.standing?
        errors.add(:base, "That repeat isn't one we understand.")
      elsif rule.until_date && due_on && rule.until_date < due_on
        errors.add(:base, "That end date is before the first one.")
      end
    end

    # "Remind me at 8am" typed at 10am for a task due today is a mistake to
    # say out loud, not a reminder to drop silently. Only from the form:
    # the Today/Tomorrow buttons moving a task whose reminder already went
    # off is not an error.
    def reminder_time_is_ahead
      return unless @time_picked
      return if repeat_rule.present? || remind_time.blank? || due_on.blank? || completed?
      return unless remind_time_changed? || due_on_changed?

      moment = one_shot_moment
      errors.add(:remind_time, "is already past for that day") if moment && moment.past?
    end

    def one_shot_moment
      hour, minute = remind_time.to_s.split(":").map(&:to_i)
      return nil if hour.nil?

      zone.local(due_on.year, due_on.month, due_on.day, hour, minute.to_i)
    end

    # Keeps the one schedule reminder saying what the task's fields say.
    def sync_schedule_reminder
      @picked = nil
      @time_picked = false
      return if @coming_round
      return unless saved_change_to_repeat_rule? || saved_change_to_remind_time? || saved_change_to_due_on? ||
                    saved_change_to_title? || saved_change_to_completed_at? || saved_change_to_id?

      reminder = reminders.find_by(schedule: true)
      if repeat_rule.present?
        sync_routine(reminder)
      elsif remind_time.present? && due_on && !completed?
        sync_one_shot(reminder)
      else
        reminder&.destroy!
      end
      association(:schedule_reminder).reset
    end

    # A repeating task: one standing reminder. Its first moment is where the
    # series starts — the due day for a new or changed rule — and the task
    # is then due on that first occurrence. A new time keeps the series on
    # the occurrence it is waiting for. Moving just the due day ("do it
    # tomorrow instead") moves this time round, not the series.
    def sync_routine(reminder)
      restart = reminder.nil? || !reminder.standing? || reminder.rule != repeat_rule
      reminder = reminders.build(user: user, schedule: true) if reminder.nil? || reminder.delivered_at
      # A new or changed rule starts on the first day on or after the due
      # day that fits it — today's chore is on today's list even when the
      # hour for today's ping has gone. A new time keeps the series on the
      # occurrence it is waiting for.
      start = restart ? first_occurrence_day : reminder.local_deliver_at.to_date
      reminder.assign_attributes(
        rule: repeat_rule, lead_minutes: nil, body: title.to_s.truncate(Reminder::MAX_BODY),
        silent: remind_time.blank?,
        # A silent chore comes round at the start of its day; a pinged one
        # at the time picked.
        deliver_on: start, deliver_time: remind_time || "00:00"
      )
      reminder.save!

      update_column(:due_on, start) if restart && !completed? && start && due_on != start
    end

    def first_occurrence_day
      from = due_on || Date.current
      recurrence.occurrences(zone.local(from.year, from.month, from.day)).first&.to_date || from
    end

    # A task with a time and no repeat: one reminder at that time on the due
    # day, re-armed when either moves. A moment already past is left alone —
    # the reminder that went off stays delivered rather than firing again.
    def sync_one_shot(reminder)
      moment = one_shot_moment
      return if reminder && reminder.rule.nil? && reminder.deliver_at == moment
      return reminder&.destroy! if moment.nil? || moment.past?

      reminder ||= reminders.build(user: user, schedule: true)
      reminder.update!(rule: nil, lead_minutes: nil, silent: false, delivered_at: nil, deliver_at: moment,
                       body: title.to_s.truncate(Reminder::MAX_BODY))
    end
end
