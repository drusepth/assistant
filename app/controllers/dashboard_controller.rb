class DashboardController < ApplicationController
  def show
    @overdue_tasks = visible_tasks.open.where(due_on: ...Date.current).order(:due_on)
    @due_today_tasks = visible_tasks.open.where(due_on: Date.current)
    @upcoming_events = Event.visible_to(Current.user)
      .overlapping(Time.current..7.days.from_now.end_of_day).includes(:sections).limit(8)
    @suggestions = Current.user.suggestions.actionable.order(created_at: :desc).includes(:sections).limit(5)
    @hero = Households::Hero.new(Current.user)
    @board = Dashboard::Board.new(Current.user)

    # Blank records for the header's inline quick-add forms.
    @quick_task = Current.user.tasks.new
    @quick_note = Current.user.notes.new
    @quick_event = Current.user.events.new
    @quick_goal = Current.user.goals.new
  end

  private
    def visible_tasks
      Task.visible_to(Current.user).includes(:sections)
    end
end
