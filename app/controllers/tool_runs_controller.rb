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

  private
    def set_tool
      @tool = Tool.find!(params[:tool_slug])
    end

    def load_input_choices
      @document_choices = Document.visible_to(Current.user).order(created_at: :desc) if @tool.inputs.any?(&:document?)
      @person_choices = Person.visible_to(Current.user).order(:name) if @tool.inputs.any?(&:person?)
      # Hobby lenses (D21); with none yet the form falls back to free text,
      # so the Hobbies tools work before any lens exists.
      @hobby_choices = (Section.find_by(slug: "hobbies")&.children || Section.none) if @tool.inputs.any?(&:hobby?)
    end

    # `new` accepts the same params so "Run again" can prefill from a
    # previous run's inputs.
    def input_params
      params.fetch(:inputs, {}).permit(*@tool.inputs.map(&:name)).to_h
    end
end
