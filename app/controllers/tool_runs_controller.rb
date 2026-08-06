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
  def recap
    run = Current.user.tool_runs.find(params[:id])
    ChatRecapJob.perform_later(run) if run.chat? && run.tool_run_messages.conversational.exists?
    redirect_to run
  end

  private
    def set_tool
      @tool = Tool.find!(params[:tool_slug])
    end

    def load_input_choices
      @document_choices = Document.visible_to(Current.user).order(created_at: :desc) if @tool.inputs.any?(&:document?)
      @person_choices = Person.visible_to(Current.user).order(:name) if @tool.inputs.any?(&:person?)
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
