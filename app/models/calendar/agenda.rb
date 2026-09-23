# What the calendar shows over a run of days (the month grid, a week, one
# day): events, tasks on their due date, and the moments reminders fire,
# as one list per day in the order a person reads a day — the things with
# no time first (all-day events, what's due), then everything with a clock
# time, events and reminders interleaved.
#
# Each kind is a layer the viewer can switch off. Events and tasks come
# through `visible_to`, like every other read of a primitive; reminders are
# delivery rather than content, so only the viewer's own.
module Calendar
  class Agenda
    LAYERS = %w[ events tasks reminders ].freeze

    # One thing on one day. `at` is the clock time it shows at on that day,
    # or nil for the untimed: an all-day event, the continuing days of a
    # multi-day one, a task.
    Entry = Data.define(:kind, :record, :at) do
      def title = kind == :reminder ? record.body : record.title

      def own?(user) = record.user_id == user.id

      # Only what the viewer could edit anyway, and only the kinds whose
      # date is theirs to change by dragging: a reminder is a time you armed,
      # and moving it belongs in its own form.
      def movable_by?(user) = kind != :reminder && own?(user)

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
          reminder_entries(entries) if layers.include?("reminders")
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
      # done when.
      def task_entries(entries)
        Task.visible_to(@user).where(due_on: days).includes(:sections, :user).find_each do |task|
          entries[task.due_on] << Entry.new(kind: :task, record: task, at: nil)
        end
      end

      # A standing reminder stores only its next delivery, so its rule is
      # expanded forward from there; the fires already past aren't stored,
      # and a past month shows only one-shots.
      def reminder_entries(entries)
        reminders = @user.reminders.where(deliver_at: ...window.end)
          .where("reminders.rule IS NOT NULL OR reminders.deliver_at >= ?", window.begin)
          .includes(:subject)

        reminders.each do |reminder|
          moments = if reminder.standing? && reminder.delivered_at.nil? && reminder.recurrence&.standing?
            reminder.recurrence.occurrences(reminder.local_deliver_at).lazy
              .take_while { |at| at <= window.end }.select { |at| window.cover?(at) }.to_a
          else
            window.cover?(reminder.deliver_at) ? [ reminder.local_deliver_at ] : []
          end

          moments.each do |at|
            entries[at.in_time_zone.to_date] << Entry.new(kind: :reminder, record: reminder, at: at.in_time_zone)
          end
        end
      end
  end
end
