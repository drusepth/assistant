module Tasks
  # The composer on a task page's embedded conversation (D30). The run is
  # created lazily on the first message — already `done` (live), seeded with
  # the task's stored guiding questions as the assistant's opening — so a
  # task page costs zero model calls until the user actually talks back.
  # Own tasks only: conversations are the owner's private surface, like
  # every tool run.
  class ConversationsController < ApplicationController
    # The conversation as its own screen (D-chat-shell) — where a phone goes
    # instead of squeezing the panel into the task page. The run may not exist
    # yet, which is fine: the surface renders the task's openers and creates it
    # on the first message, exactly as the embedded panel does.
    def show
      task = Current.user.tasks.find(params[:task_id])

      render "tasks/conversations/show", locals: { task: task, run: task.conversation }
    end

    def create
      task = Current.user.tasks.find(params[:task_id])
      if params[:content].present?
        run = task.conversation || start_conversation(task)
        run.tool_run_messages.create!(role: :user, content: params[:content],
          client_token: params[:client_token].presence)
        ChatTurnJob.perform_later(run)
      end
      redirect_to task
    end

    private
      def start_conversation(task)
        run = Current.user.tool_runs.create!(tool_slug: "task_chat", subject: task, status: :done)
        task.conversation_openers.each do |question|
          run.tool_run_messages.create!(role: :assistant, content: question)
        end
        run
      end
  end
end
