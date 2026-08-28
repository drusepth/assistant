class TasksController < ApplicationController
  DONE_COLUMN_LIMIT = 20

  before_action :set_own_task, only: %i[ edit update destroy complete reopen reschedule move ]

  # One section, two surfaces (D-tasks-two-surfaces): the board is the daily
  # default; ?tab=goals is the planning destination.
  def index
    @tab = params[:tab] == "goals" ? "goals" : "board"
    goals = Goal.visible_to(Current.user).includes(:sections, :tasks, :user)
    @new_goal = Current.user.goals.new

    if @tab == "goals"
      @active_goals = Goal.by_attention(goals.active.to_a)
      @paused_goals = goals.paused.order(updated_at: :desc)
      @achieved_goals = goals.done.order(updated_at: :desc)
    else
      scope = Task.visible_to(Current.user).includes(:sections, :user, :goal)
      open_tasks = scope.open.order(Arel.sql("due_on IS NULL, due_on ASC, created_at ASC")).to_a
      @today_tasks, @later_tasks = open_tasks.partition(&:for_today?)
      @done_tasks = scope.completed.order(completed_at: :desc).limit(DONE_COLUMN_LIMIT)
      @strip_goals = Goal.by_attention(goals.active.to_a)
    end
  end

  def show
    @task = Task.visible_to(Current.user).find(params[:id])
    # The embedded conversation (D30) is the owner's private surface —
    # household members who can see a shared task never see the chat.
    @conversation = @task.conversation if @task.user_id == Current.user.id
  end

  def new
    # `title` is prefilled by the surfaces that already know what the task
    # is — the reader's "Make a task" on a feed item (D-feed-reader).
    @task = Current.user.tasks.new(params.permit(:title, :due_on, :goal_id, section_ids: []))
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

  # Claiming a task for a day, and taking that back. The row it was on has
  # just animated off the list (D-row-send-off), which says "gone" but never
  # "gone where" — and until there was a way back, a mis-tap on a phone cost
  # a hunt through Tasks to put right. So the move says what it did and
  # carries its own undo, which is nothing more than a reschedule to where
  # the task was: `to` takes a plain date and "none" as well as the two
  # words the buttons send.
  def reschedule
    was = @task.due_on
    @task.update!(due_on: reschedule_target)

    flash[:notice] = "“#{@task.title.truncate(48)}” moved to #{due_phrase(@task.due_on)}."
    flash[:undo] = { "label" => "Undo", "url" => reschedule_task_path(@task, to: was&.to_fs(:iso8601) || "none") }
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
    # The two words the buttons send, an ISO date (which is what an undo
    # sends), or "none" for a task that had no date to begin with. Anything
    # else — including a date that parses but doesn't exist — means today,
    # which is what this action did for every unrecognised `to` before.
    def reschedule_target
      case params[:to]
      when "tomorrow" then Date.tomorrow
      when "none" then nil
      when /\A\d{4}-\d{2}-\d{2}\z/ then Date.iso8601(params[:to])
      else Date.current
      end
    rescue Date::Error
      Date.current
    end

    # How the notice names where the task landed. Deliberately not
    # `task_due_label`: that one answers "how late is this" in a list, and
    # "moved to 9 days late" is not a sentence.
    def due_phrase(date)
      return "no date" if date.nil?
      return "today" if date == Date.current
      return "tomorrow" if date == Date.tomorrow

      date.strftime("%b %-d")
    end

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
