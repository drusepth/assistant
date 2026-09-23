# D-reminders-on-tasks: a reminder is always set on something. Every pending
# reminder that hung on nothing becomes a task that carries it, so "Take the
# trash to the curb" lands on the board as the chore it always was:
#
# - a repeating one becomes that task's routine, and the task is due on the
#   next occurrence;
# - a one-shot becomes "remind me at <time>" on a task due that day, stored
#   the way the task form stores it — a lead counted from the start of the
#   due day, so rescheduling the task moves it.
#
# Routines already on tasks get the same due day, since a repeating task is
# now due on its next occurrence. Delivered reminders are history and are
# left as they are. Plain SQL, not the models, so later model changes can't
# change what this did.
class MoveStandaloneRemindersOntoTasks < ActiveRecord::Migration[8.1]
  DAY_START_HOUR = 9

  def up
    now = Time.current

    rows = select_rows(<<~SQL)
      SELECT reminders.id, reminders.user_id, reminders.body, reminders.deliver_at, reminders.rule, households.time_zone
      FROM reminders
      JOIN users ON users.id = reminders.user_id
      LEFT JOIN households ON households.id = users.household_id
      WHERE reminders.subject_id IS NULL AND reminders.delivered_at IS NULL
    SQL

    rows.each do |id, user_id, body, deliver_at, rule, time_zone|
      local = parse_time(deliver_at).in_time_zone(zone_for(time_zone))
      task_id = insert(<<~SQL.squish)
        INSERT INTO tasks (user_id, title, due_on, bucket, created_at, updated_at)
        VALUES (#{user_id.to_i}, #{quote(body.to_s.truncate(255))}, #{quote(local.to_date.iso8601)}, 0, #{quote(now)}, #{quote(now)})
      SQL
      lead = rule.present? ? "NULL" : (DAY_START_HOUR * 60 - (local.hour * 60 + local.min)).to_s
      execute(<<~SQL.squish)
        UPDATE reminders SET subject_type = 'Task', subject_id = #{task_id.to_i}, lead_minutes = #{lead},
          updated_at = #{quote(now)} WHERE id = #{id.to_i}
      SQL
    end

    select_rows(<<~SQL).each do |task_id, deliver_at, time_zone|
      SELECT tasks.id, MIN(reminders.deliver_at), households.time_zone
      FROM tasks
      JOIN reminders ON reminders.subject_type = 'Task' AND reminders.subject_id = tasks.id
        AND reminders.rule IS NOT NULL AND reminders.delivered_at IS NULL
      JOIN users ON users.id = tasks.user_id
      LEFT JOIN households ON households.id = users.household_id
      WHERE tasks.due_on IS NULL AND tasks.completed_at IS NULL
      GROUP BY tasks.id, households.time_zone
    SQL
      day = parse_time(deliver_at).in_time_zone(zone_for(time_zone)).to_date
      execute("UPDATE tasks SET due_on = #{quote(day.iso8601)} WHERE id = #{task_id.to_i}")
    end
  end

  def down
  end

  private
    def zone_for(name) = (name.presence && ActiveSupport::TimeZone[name]) || Time.zone

    def parse_time(value) = value.is_a?(String) ? Time.zone.parse("#{value} UTC") : value

    def quote(value) = connection.quote(value)
end
