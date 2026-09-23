# What the calendar shows over a run of days (the month grid, a week, one
# day): events, and tasks on their due date, as one list per day in the
# order a person reads a day — the things with no time first (all-day
# events, what's due), then everything with a clock time.
#
# A reminder is not a thing of its own here (D-reminders-on-tasks): a task
# with "Remind me at 4pm" sits at 4pm on its day, and a repeating task shows
# on each day ahead that it will come round, faded, as `:repeat`. An
# event's own reminders ride the event. Each kind is a layer the viewer can
# switch off, and both come through `visible_to`, like every other read of
# a primitive.
module Calendar
  class Agenda
    LAYERS = %w[ events tasks ].freeze

    # One thing on one day. `at` is the clock time it shows at on that day,
    # or nil for the untimed: an all-day event, the continuing days of a
    # multi-day one, a task with no reminder time. `kind` is :event, :task,
    # or :repeat — a repeating task on a day ahead it will come round.
    Entry = Data.define(:kind, :record, :at) do
      def title = record.title

      def own?(user) = record.user_id == user.id

      # Only what the viewer could edit anyway. A repeat is where the rule
      # puts the task next, not a row of its own to drag.
      def movable_by?(user) = kind != :repeat && own?(user)

      def overdue?
        kind == :task && !record.completed? && record.due_on < Date.current
      end

      def sort_key
        untimed_rank = { event: 0, task: 1 }.fetch(kind, 2)
        at ? [ 1, at.to_i, 0 ] : [ 0, untimed_rank, record.try(:completed?) ? 1 : 0 ]
      end
    end

    attr_reader :days, :layers

    def initialize(user:, days:, layers: LAYERS)
      @user = user
      @days = days
      @layers = layers
    end

    def on(day) = by_day.fetch(day, [])

    # The viewer's own open tasks whose day has passed. A past month scrolls
    # them out of sight, which is exactly when they need saying.
    def overdue_tasks
      return Task.none unless layers.include?("tasks")

      @user.tasks.open.where(due_on: ...Date.current).includes(:sections).order(:due_on, :created_at)
    end

    private
      def by_day
        @by_day ||= begin
          entries = Hash.new { |hash, day| hash[day] = [] }
          event_entries(entries) if layers.include?("events")
          task_entries(entries) if layers.include?("tasks")
          entries.transform_values { |list| list.sort_by(&:sort_key) }
        end
      end

      def window = Time.zone.local(days.first.year, days.first.month, days.first.day)..days.last.in_time_zone.end_of_day

      def event_entries(entries)
        Event.visible_to(@user).overlapping(window).includes(:sections, :user).find_each do |event|
          first_day = event.starts_at.to_date
          span_start = [ first_day, days.first ].max
          span_end = [ (event.ends_at || event.starts_at).to_date, days.last ].min
          (span_start..span_end).each do |day|
            timed = !event.all_day? && day == first_day
            entries[day] << Entry.new(kind: :event, record: event, at: (event.starts_at if timed))
          end
        end
      end

      # Done tasks stay on their day, so a past month still says what got
      # done when. A task with a reminder time sits at that time, and only
      # its owner sees it: the time is their ping, not the task's content.
      def task_entries(entries)
        Task.visible_to(@user).where(due_on: days).includes(:sections, :user).find_each do |task|
          entries[task.due_on] << Entry.new(kind: :task, record: task, at: remind_moment(task, task.due_on))
        end
        repeat_entries(entries)
      end

      # A repeating task is one row, due on its current occurrence; the days
      # after that it will come round again are drawn from its rule, so the
      # month ahead shows trash night every Thursday. Past days show only
      # what the row itself says.
      def repeat_entries(entries)
        Task.visible_to(@user).where.not(repeat_rule: nil).where(due_on: ...days.last)
          .includes(:sections, user: :household).find_each do |task|
          rule = task.recurrence
          next unless rule&.standing?

          from = [ task.due_on + 1, days.first, Date.current ].max
          zone = task.user.household.zone
          rule.occurrences(zone.local(task.due_on.year, task.due_on.month, task.due_on.day)).lazy
            .map(&:to_date).take_while { |day| day <= days.last }.select { |day| day >= from }
            .each { |day| entries[day] << Entry.new(kind: :repeat, record: task, at: remind_moment(task, day)) }
        end
      end

      def remind_moment(task, day)
        return nil unless task.remind_time && task.user_id == @user.id

        hour, minute = task.remind_time.split(":").map(&:to_i)
        task.user.household.zone.local(day.year, day.month, day.day, hour, minute).in_time_zone
      end
  end
end
