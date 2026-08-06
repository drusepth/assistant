class TodayController < ApplicationController
  def show
    tasks = Task.visible_to(Current.user).open.includes(:sections)
    @overdue_tasks = tasks.where(due_on: ...Date.current).order(:due_on)
    @today_tasks = tasks.where(due_on: Date.current)
    @tomorrow_tasks = tasks.where(due_on: Date.tomorrow)
    @unscheduled_tasks = tasks.where(due_on: nil).order(created_at: :desc)

    events = Event.visible_to(Current.user).includes(:sections)
    @today_events = events.between(Time.current.beginning_of_day..Time.current.end_of_day)
    @tomorrow_events = events.between(Date.tomorrow.beginning_of_day..Date.tomorrow.end_of_day)
    @week_events = events.between((Date.tomorrow + 1).beginning_of_day..7.days.from_now.end_of_day)
  end
end
