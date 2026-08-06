class ToolRunsController < ApplicationController
  before_action :set_tool, only: %i[ new create ]
  before_action :load_document_choices, only: %i[ new create ]

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

    def load_document_choices
      return unless @tool.inputs.any?(&:document?)

      @document_choices = Document.visible_to(Current.user).order(created_at: :desc)
    end

    # `new` accepts the same params so "Run again" and next-step links can
    # prefill from earlier inputs. Checkbox inputs arrive as arrays.
    def input_params
      permitted = @tool.inputs.map { |input| input.checkboxes? ? { input.name => [] } : input.name }
      params.fetch(:inputs, {}).permit(*permitted).to_h
    end
end
