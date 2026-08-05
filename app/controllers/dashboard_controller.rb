class DashboardController < ApplicationController
  def show
    @overdue_tasks = visible_tasks.open.where(due_on: ...Date.current).order(:due_on)
    @due_today_tasks = visible_tasks.open.where(due_on: Date.current)
    @upcoming_events = Event.visible_to(Current.user)
      .between(Time.current..7.days.from_now.end_of_day).includes(:sections).limit(8)
    @active_goals = Goal.visible_to(Current.user).active.includes(:tasks)
    @recent_documents = Document.visible_to(Current.user).order(created_at: :desc).includes(:sections).limit(5)
  end

  private
    def visible_tasks
      Task.visible_to(Current.user).includes(:sections)
    end
end
