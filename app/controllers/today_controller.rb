class TodayController < ApplicationController
  UNSCHEDULED_LIMIT = 5

  def show
    tasks = Task.visible_to(Current.user).open.includes(:sections)
    @overdue_tasks = tasks.where(due_on: ...Date.current).order(:due_on)
    @today_tasks = tasks.where(due_on: Date.current)
    @prep_range = prep_range
    @prep_tasks = tasks.where(due_on: @prep_range).order(:due_on)
    @unscheduled_count = tasks.where(due_on: nil).count
    @unscheduled_tasks = tasks.where(due_on: nil).order(created_at: :desc).limit(UNSCHEDULED_LIMIT)

    events = Event.visible_to(Current.user).includes(:sections)
    @today_events = events.overlapping(Time.current.beginning_of_day..Time.current.end_of_day)
    @prep_events = events.overlapping(@prep_range.first.beginning_of_day..@prep_range.last.end_of_day)
    @early_events = @prep_events.select { |event| event.starts_at.to_date == Date.tomorrow && event.early_morning? }
    @week_events_by_day = events
      .between((@prep_range.last + 1).beginning_of_day..7.days.from_now.end_of_day)
      .group_by { |event| event.starts_at.to_date }
  end

  private
    # On Fridays the next workday is Monday, so prep covers the whole weekend.
    def prep_range
      Date.current.friday? ? Date.tomorrow..(Date.current + 3) : Date.tomorrow..Date.tomorrow
    end
end
