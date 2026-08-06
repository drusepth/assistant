class TasksController < ApplicationController
  before_action :set_own_task, only: %i[ edit update destroy complete reopen reschedule ]

  def index
    scope = Task.visible_to(Current.user).includes(:sections, :user)
    if params[:filter] == "completed"
      @filter = "completed"
      @tasks = scope.completed.order(completed_at: :desc)
    else
      @filter = "open"
      @tasks = scope.open.order(Arel.sql("due_on IS NULL, due_on ASC"))
    end
  end

  def show
    @task = Task.visible_to(Current.user).find(params[:id])
  end

  def new
    @task = Current.user.tasks.new(params.permit(:due_on, :goal_id))
  end

  def create
    @task = Current.user.tasks.new(task_params)
    if @task.save
      redirect_to tasks_path, notice: "Task added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      redirect_to @task, notice: "Task updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy!
    redirect_to tasks_path, notice: "Task deleted."
  end

  def complete
    @task.complete!
    redirect_back fallback_location: tasks_path
  end

  def reopen
    @task.reopen!
    redirect_back fallback_location: tasks_path
  end

  def reschedule
    @task.update!(due_on: params[:to] == "tomorrow" ? Date.tomorrow : Date.current)
    redirect_back fallback_location: today_path
  end

  private
    def set_own_task
      @task = Current.user.tasks.find(params[:id])
    end

    def task_params
      params.expect(task: [ :title, :notes, :due_on, :goal_id, section_ids: [] ])
    end
end
