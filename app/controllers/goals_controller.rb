class GoalsController < ApplicationController
  before_action :set_own_goal, only: %i[ edit update destroy complete reopen pause resume break_down ]

  # Goals live inside the Tasks section now; the old boards URL just forwards.
  def index
    redirect_to tasks_path
  end

  def show
    @goal = Goal.visible_to(Current.user).find(params[:id])
    @tasks = @goal.tasks.visible_to(Current.user).order(Arel.sql("completed_at IS NOT NULL, due_on IS NULL, due_on ASC"))
    @events = @goal.events.visible_to(Current.user).order(:starts_at)
  end

  def new
    # `title` rides along from a quick-add's "Full form" link.
    @goal = Current.user.goals.new(params.permit(:title))
  end

  def create
    @goal = Current.user.goals.new(goal_params)
    if @goal.save
      @goal.enqueue_break_down!
      notice = @goal.breaking_down? ? "Goal added — your assistant is breaking it into steps." : "Goal added."
      # Capture lands on the goal's own page (D-tasks-two-surfaces): the plan
      # streams in there, and editing it flows straight into doing it.
      redirect_to return_to_path(goal_path(@goal)), notice: notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @goal.update(goal_params)
      redirect_to @goal, notice: "Goal updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @goal.destroy!
    redirect_to tasks_path, notice: "Goal deleted."
  end

  def complete
    @goal.update!(status: :done)
    redirect_back fallback_location: goal_path(@goal)
  end

  def reopen
    @goal.update!(status: :active)
    redirect_back fallback_location: goal_path(@goal)
  end

  # Shelving without shame (D-goal-pause): one click each way, no ceremony.
  def pause
    @goal.pause!
    redirect_back fallback_location: goal_path(@goal), notice: "Goal paused — it's parked on the Goals tab whenever you're ready."
  end

  def resume
    @goal.resume!
    redirect_back fallback_location: goal_path(@goal), notice: "Goal resumed."
  end

  def break_down
    if @goal.auto_sort_profile
      BreakDownGoalJob.perform_later(@goal, append: @goal.tasks.any?)
      redirect_to @goal, notice: "Asking your assistant for steps."
    else
      redirect_to @goal, alert: "Configure a model in Settings to get AI-suggested steps."
    end
  end

  private
    def set_own_goal
      @goal = Current.user.goals.find(params[:id])
    end

    def goal_params
      params.expect(goal: [ :title, :description, :target_on, section_ids: [] ])
    end
end
