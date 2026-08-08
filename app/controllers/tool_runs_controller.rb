class ToolRunsController < ApplicationController
  before_action :set_tool, only: %i[ new create ]
  before_action :load_input_choices, only: %i[ new create ]

  def new
    @tool_run = Current.user.tool_runs.new(tool_slug: @tool.slug, inputs: input_params)
  end

  def create
    @tool_run = Current.user.tool_runs.new(tool_slug: @tool.slug, inputs: input_params)
    if @tool_run.save
      ToolRunJob.perform_later(@tool_run)
      redirect_to @tool_run
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @tool_run = Current.user.tool_runs.find(params[:id])
  end

  # "Save a recap" on a chat run (D29) — the explicit click that turns a
  # session into an owned Note (D20: nothing lands without the user asking).
  # recap_requested_at is the in-flight marker: it drives the button's
  # "Saving recap…" state and keeps a double-click from filing two notes.
  def recap
    run = Current.user.tool_runs.find(params[:id])
    if run.chat? && run.tool_run_messages.conversational.exists? && !run.recap_pending?
      run.update_column(:recap_requested_at, Time.current)
      ChatRecapJob.perform_later(run)
    end
    redirect_to run
  end

  # "Try again" after a failed turn: drop the failure notice and re-enqueue
  # the reply — the user's message is answered without retyping it.
  def retry_reply
    run = Current.user.tool_runs.find(params[:id])
    if run.reply_failed?
      run.tool_run_messages.ordered.last.destroy!
      ChatTurnJob.perform_later(run)
    end
    redirect_to run
  end

  private
    def set_tool
      @tool = Tool.find!(params[:tool_slug])
    end

    def load_input_choices
      @document_choices = Document.visible_to(Current.user).order(created_at: :desc) if @tool.inputs.any?(&:document?)
      # Circle first (D30) — the people you're tending are almost always the
      # ones a People tool is about.
      @person_choices = Person.visible_to(Current.user).order(keep_in_touch: :desc, name: :asc) if @tool.inputs.any?(&:person?)
      # Hobby lenses (D25); with none yet the form falls back to free text,
      # so the Hobbies tools work before any lens exists.
      @hobby_choices = (Section.find_by(slug: "hobbies")&.children || Section.none) if @tool.inputs.any?(&:hobby?)
    end

    # `new` accepts the same params so "Run again" and next-step links can
    # prefill from earlier inputs. Checkbox inputs arrive as arrays.
    def input_params
      permitted = @tool.inputs.map { |input| input.checkboxes? ? { input.name => [] } : input.name }
      params.fetch(:inputs, {}).permit(*permitted).to_h
    end
end
