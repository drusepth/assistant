class TasksController < ApplicationController
  DONE_COLUMN_LIMIT = 20

  before_action :set_own_task, only: %i[ edit update destroy complete reopen reschedule move ]

  def index
    scope = Task.visible_to(Current.user).includes(:sections, :user, :goal)
    open_tasks = scope.open.order(Arel.sql("due_on IS NULL, due_on ASC, created_at ASC")).to_a
    @today_tasks, @later_tasks = open_tasks.partition(&:for_today?)
    @done_tasks = scope.completed.order(completed_at: :desc).limit(DONE_COLUMN_LIMIT)

    @goals = Goal.visible_to(Current.user).active.includes(:sections, :tasks, :user).order(created_at: :desc)
    @new_goal = Current.user.goals.new
  end

  def show
    @task = Task.visible_to(Current.user).find(params[:id])
    # The embedded conversation (D30) is the owner's private surface —
    # household members who can see a shared task never see the chat.
    @conversation = @task.conversation if @task.user_id == Current.user.id
  end

  def new
    @task = Current.user.tasks.new(params.permit(:due_on, :goal_id, section_ids: []))
  end

  def create
    @task = Current.user.tasks.new(task_params)
    if @task.save
      @task.enqueue_auto_sort!
      redirect_to return_to_path(tasks_path), notice: "Task added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      # "Save & complete" on the answer card (D30): writing the answer is
      # how a mental task finishes, so the two come as one click.
      if params[:save_and_complete].present? && !@task.completed?
        complete_and_celebrate!
        redirect_to @task, notice: "Answer saved — task completed."
      else
        redirect_to @task, notice: "Task updated."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy!
    redirect_to tasks_path, notice: "Task deleted."
  end

  def complete
    complete_and_celebrate!
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

  # Board moves. Done is completion, not a bucket, so moving in and out of
  # that column completes/reopens the task.
  def move
    case params.expect(:column)
    when "done"
      complete_and_celebrate!
    when "today"
      @task.reopen! if @task.completed?
      @task.update!(bucket: :today)
    when "later"
      @task.reopen! if @task.completed?
      # A due date that has already arrived would pull the task straight back
      # into Today, so "not today" also nudges the date to tomorrow.
      updates = { bucket: :later }
      updates[:due_on] = Date.tomorrow if @task.due_on && @task.due_on <= Date.current
      @task.update!(updates)
    else
      raise ActionController::BadRequest, "unknown column"
    end
    redirect_back fallback_location: tasks_path
  end

  private
    # Finishing a task is the app's one genuinely good moment, so it gets a
    # party (D-task-celebration). The redirect that follows would wipe an
    # animation started here, so the celebration rides the flash and fires on
    # the page that comes back.
    def complete_and_celebrate!
      @task.complete!
      payload = Tasks::Celebration.for(@task)
      flash[:celebrate] = payload.to_json if payload
    end

    def set_own_task
      @task = Current.user.tasks.find(params[:id])
    end

    def task_params
      params.expect(task: [ :title, :notes, :due_on, :goal_id, :resolution, section_ids: [] ])
    end
end
