# D-reminders-on-tasks: a task's schedule is the task's own. `repeat_rule`
# and `remind_time` are columns on the task, and the ping they imply is one
# reminder row the task keeps in step with them, marked `schedule` so
# nothing has to guess which reminder the form owns. `silent` lets that row
# bring a chore back onto the board on its day without a notification.
#
# The data half:
#
# - every pending reminder that hung on nothing becomes a task that carries
#   it — a repeating one as that task's repeat and time, due on its next
#   occurrence; a one-shot as "remind me at <time>" on a task due that day;
# - every routine already on a task (its first pending repeating reminder)
#   moves its rule and time onto the task and becomes the task's schedule
#   reminder; an undated one gets its next occurrence as the due day.
#
# Delivered reminders are history and are left as they are. Plain SQL, not
# the models, so later model changes can't change what this did.
class MoveTaskScheduleOntoTasks < ActiveRecord::Migration[8.1]
  def up
    add_column :tasks, :repeat_rule, :string
    add_column :tasks, :remind_time, :string
    add_column :reminders, :schedule, :boolean, default: false, null: false
    add_column :reminders, :silent, :boolean, default: false, null: false

    now = Time.current

    standalone = select_rows(<<~SQL)
      SELECT reminders.id, reminders.user_id, reminders.body, reminders.deliver_at, reminders.rule, households.time_zone
      FROM reminders
      JOIN users ON users.id = reminders.user_id
      LEFT JOIN households ON households.id = users.household_id
      WHERE reminders.subject_id IS NULL AND reminders.delivered_at IS NULL
    SQL

    standalone.each do |id, user_id, body, deliver_at, rule, time_zone|
      local = local_time(deliver_at, time_zone)
      task_id = insert(<<~SQL.squish)
        INSERT INTO tasks (user_id, title, due_on, repeat_rule, remind_time, bucket, created_at, updated_at)
        VALUES (#{user_id.to_i}, #{quote(body.to_s.truncate(255))}, #{quote(local.to_date.iso8601)},
          #{quote(rule.presence)}, #{quote(local.strftime("%H:%M"))}, 0, #{quote(now)}, #{quote(now)})
      SQL
      execute(<<~SQL.squish)
        UPDATE reminders SET subject_type = 'Task', subject_id = #{task_id.to_i}, schedule = 1, lead_minutes = NULL,
          updated_at = #{quote(now)} WHERE id = #{id.to_i}
      SQL
    end

    routines = select_rows(<<~SQL)
      SELECT reminders.id, tasks.id, tasks.due_on, tasks.completed_at, reminders.deliver_at, reminders.rule, households.time_zone
      FROM reminders
      JOIN tasks ON reminders.subject_type = 'Task' AND reminders.subject_id = tasks.id
      JOIN users ON users.id = tasks.user_id
      LEFT JOIN households ON households.id = users.household_id
      WHERE reminders.rule IS NOT NULL AND reminders.delivered_at IS NULL AND reminders.schedule = 0
        AND tasks.repeat_rule IS NULL
      ORDER BY reminders.id
    SQL

    claimed = {}
    routines.each do |reminder_id, task_id, due_on, completed_at, deliver_at, rule, time_zone|
      next if claimed[task_id]

      claimed[task_id] = true
      local = local_time(deliver_at, time_zone)
      due = due_on.nil? && completed_at.nil? ? ", due_on = #{quote(local.to_date.iso8601)}" : ""
      execute(<<~SQL.squish)
        UPDATE tasks SET repeat_rule = #{quote(rule)}, remind_time = #{quote(local.strftime("%H:%M"))}#{due}
        WHERE id = #{task_id.to_i}
      SQL
      execute("UPDATE reminders SET schedule = 1 WHERE id = #{reminder_id.to_i}")
    end
  end

  def down
    remove_column :reminders, :silent
    remove_column :reminders, :schedule
    remove_column :tasks, :remind_time
    remove_column :tasks, :repeat_rule
  end

  private
    def local_time(value, time_zone)
      time = value.is_a?(String) ? Time.zone.parse("#{value} UTC") : value
      time.in_time_zone((time_zone.presence && ActiveSupport::TimeZone[time_zone]) || Time.zone)
    end

    def quote(value) = connection.quote(value)
end
