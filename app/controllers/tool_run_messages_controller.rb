# The composer on a chat-kind run's page (D29): store the user's turn,
# enqueue the reply. Only the run's owner ever reaches the run at all.
class ToolRunMessagesController < ApplicationController
  before_action :set_run

  # Paging backwards through a windowed transcript: the batch of turns older
  # than the cursor, plus a replacement seam carrying the next cursor (or
  # nothing, when the conversation has been read to its start).
  def index
    head :unprocessable_entity and return unless @run.chat?

    cursor = @run.tool_run_messages.find_by(id: params[:before])
    head :bad_request and return unless cursor

    @messages, @earlier = @run.tool_run_messages.window(before: cursor)

    respond_to do |format|
      format.turbo_stream
      # No JavaScript, no windowing to page through — the run page renders
      # what it renders.
      format.html { redirect_to @run }
    end
  end

  def create
    head :unprocessable_entity and return unless @run.chat? && @run.done?

    if params[:content].present?
      @run.tool_run_messages.create!(role: :user, content: params[:content])
      ChatTurnJob.perform_later(@run)
    end
    redirect_to @run
  end

  private
    def set_run
      @run = Current.user.tool_runs.find(params[:tool_run_id])
    end
end
