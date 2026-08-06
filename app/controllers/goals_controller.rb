class GoalsController < ApplicationController
  before_action :set_own_goal, only: %i[ edit update destroy move ]

  def index
    goals = Goal.visible_to(Current.user).includes(:sections, :tasks, :user)
    @columns = Goal.statuses.keys.index_with { |status| goals.select { |goal| goal.status == status } }
  end

  def show
    @goal = Goal.visible_to(Current.user).find(params[:id])
    @tasks = @goal.tasks.visible_to(Current.user).order(Arel.sql("completed_at IS NOT NULL, due_on IS NULL, due_on ASC"))
    @events = @goal.events.visible_to(Current.user).order(:starts_at)
  end

  def new
    @goal = Current.user.goals.new
  end

  def create
    @goal = Current.user.goals.new(goal_params)
    if @goal.save
      @goal.enqueue_auto_sort!
      redirect_to goals_path, notice: "Goal added."
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
    redirect_to goals_path, notice: "Goal deleted."
  end

  def move
    status = params.expect(:status)
    raise ActionController::BadRequest, "unknown status" unless Goal.statuses.key?(status)

    @goal.update!(status: status)
    redirect_back fallback_location: goals_path
  end

  private
    def set_own_goal
      @goal = Current.user.goals.find(params[:id])
    end

    def goal_params
      params.expect(goal: [ :title, :description, :status, :target_on, section_ids: [] ])
    end
end
