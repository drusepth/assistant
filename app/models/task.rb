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
  # "At 4pm on the day" counts forward from the start of the due day; the
  # range is every minute of that day, so nothing here is on another date.
  SAME_DAY_LEADS = ((Remindable::DAY_START_HOUR - 24) * 60 + 1)..(Remindable::DAY_START_HOUR * 60)

  before_validation :default_schedule_day
  validate :schedule_is_valid
  after_save :save_schedule

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
    reminders.pending.where(rule: nil).destroy_all
    goal&.finish_if_done!
  end

  def reopen!
    update!(completed_at: nil)
    goal&.reactivate!
  end

  # The task's schedule (D-reminders-on-tasks): a due day, an optional
  # repeat, and an optional time to be pinged. Three fields on the task
  # form, one reminder row underneath — the user never manages the reminder
  # as a thing of its own.
  #
  # A routine (D-task-routines) is the repeating case: the chore's standing
  # reminder. When it fires, the task comes back onto the board.
  def routine
    reminders.standing.pending.order(:id).first
  end

  def routine? = routine.present?

  # The non-repeating case: "remind me at 4pm on the day it's due". Stored
  # as a relative reminder counting from the start of the due day, so it
  # moves when the task is rescheduled and retires when the date is cleared
  # (Remindable), with no second sync to keep. Lead times that land on an
  # earlier day ("the day before") are the task page's extra reminders, not
  # this one.
  def day_reminder
    reminders.pending.relative.where(lead_minutes: SAME_DAY_LEADS).order(:id).first
  end

  # The one reminder the task form reads and writes.
  def schedule_reminder = routine || day_reminder

  # The reminders the form doesn't manage — set from the task page.
  def extra_reminders
    managed = schedule_reminder
    reminders.pending.order(:deliver_at).reject { |reminder| reminder == managed }
  end

  # The form's fields. Each reads back from the schedule reminder, so an
  # edit form opens on what was chosen; an assigned value wins until saved.
  def repeat = @repeat || Reminder.repeat_key_for(routine&.recurrence)
  def repeat_days = @repeat_days || routine&.repeat_days || []
  def repeat_until = defined?(@repeat_until) ? @repeat_until : routine&.repeat_until
  def remind_at = defined?(@remind_at) ? @remind_at : schedule_reminder&.time_of_day

  def repeat=(key)
    @schedule_assigned = true
    @repeat = key.presence || "none"
  end

  def repeat_days=(codes)
    @schedule_assigned = true
    @repeat_days = Array(codes).compact_blank
  end

  def repeat_until=(date)
    @schedule_assigned = true
    @repeat_until = date.presence && Date.parse(date.to_s)
  rescue Date::Error
    @repeat_until = nil
  end

  def remind_at=(time)
    @schedule_assigned = true
    @remind_at = time.presence
  end

  # What a routine firing does to the board (Q-routines, D-task-routines):
  # the same row comes back — reopened if it was done, due on the day it
  # came round, pulled into Today. One durable task, never a row per
  # occurrence.
  def come_round!(on: Date.current)
    was_done = completed?
    update!(completed_at: nil, bucket: :today, due_on: on)
    goal&.reactivate! if was_done
  end

  private
    def stored_questions
      Array(guiding_questions).grep(String).map(&:strip).reject(&:empty?)
    end

    # A reminder time or a repeat needs a day to start from; with none
    # picked, that day is today.
    def default_schedule_day
      return unless @schedule_assigned
      return if repeat == "none" && remind_at.blank?

      self.due_on ||= Date.current
    end

    # Builds the one reminder the fields describe — without saving it, so a
    # bad repeat is a form error on the task rather than a half-saved pair.
    def schedule_is_valid
      return unless @schedule_assigned

      @schedule_retired = []
      @schedule_draft = nil
      current = schedule_reminder

      if repeat != "none"
        @schedule_retired << current if current && !current.standing?
        @schedule_draft = current&.standing? ? current : Reminder.new
        @schedule_draft.assign_attributes(repeat: repeat, repeat_days: repeat_days, repeat_until: repeat_until,
                                          deliver_time: remind_at || format("%02d:00", Reminder::DEFAULT_HOUR))
        # The due day is where a new series starts, and where a moved one
        # restarts. Left alone otherwise: an open chore still due on a day
        # it missed is owed, and re-reading that day as a start would skip
        # it past the occurrence it is waiting on.
        @schedule_draft.deliver_on = due_on if @schedule_draft.new_record? || due_on_changed?
      elsif remind_at.present?
        @schedule_retired << current if current&.standing?
        @schedule_draft = current && !current.standing? ? current : Reminder.new
        @schedule_draft.assign_attributes(lead_minutes: Reminder.lead_for_time_of_day(remind_at))
      else
        @schedule_retired << current if current
      end
      return unless @schedule_draft

      @schedule_draft.assign_attributes(user: user, subject: self, body: title.to_s.truncate(Reminder::MAX_BODY))
      # A relative reminder counts from the task's due day, which only
      # exists once the task's own changes are in; the draft reads it from
      # this unsaved task, so check it against what is about to be true.
      return if @schedule_draft.valid?

      @schedule_draft.errors.full_messages.each { |message| errors.add(:base, message) }
    end

    # A repeating task is due on its next occurrence: the day the routine
    # was set to start is only where the series starts, and the task's date
    # follows the reminder rather than disagreeing with it.
    def save_schedule
      return unless @schedule_assigned

      @schedule_retired.each(&:destroy!)
      if @schedule_draft
        restarted = @schedule_draft.new_record? || @schedule_draft.rule_changed? || saved_change_to_due_on?
        @schedule_draft.save!
        if @schedule_draft.standing? && restarted && !completed?
          first_day = @schedule_draft.local_deliver_at.to_date
          update_column(:due_on, first_day) if due_on != first_day
        end
      end
      @schedule_assigned = false
      @schedule_draft = nil
      @schedule_retired = []
      remove_instance_variable(:@repeat) if defined?(@repeat)
      remove_instance_variable(:@repeat_days) if defined?(@repeat_days)
      remove_instance_variable(:@repeat_until) if defined?(@repeat_until)
      remove_instance_variable(:@remind_at) if defined?(@remind_at)
    end
end
