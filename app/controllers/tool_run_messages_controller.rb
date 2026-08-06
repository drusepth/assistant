# The composer on a chat-kind run's page (D29): store the user's turn,
# enqueue the reply. Only the run's owner ever reaches the run at all.
class ToolRunMessagesController < ApplicationController
  def create
    run = Current.user.tool_runs.find(params[:tool_run_id])
    head :unprocessable_entity and return unless run.chat? && run.done?

    if params[:content].present?
      run.tool_run_messages.create!(role: :user, content: params[:content])
      ChatTurnJob.perform_later(run)
    end
    redirect_to run
  end
end
