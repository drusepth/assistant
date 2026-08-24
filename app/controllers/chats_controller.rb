# The conversation index (D-chat-index). Chat runs were reachable only by
# their own URL or by a link somebody remembered to hand-place, so a
# conversation you walked away from was effectively gone — while
# ToolRun#previous_recap has always rendered "Picking up from last time",
# implementing a resume nobody could ask for. This is the list.
#
# Owner-only, like every tool run: there is no `visible_to` path to a
# transcript, and this adds none.
class ChatsController < ApplicationController
  LIMIT = 100

  Conversation = Data.define(:run, :last_message, :turns) do
    def tool = run.tool
    def subject = run.subject

    # A subject-bound conversation (D30) belongs to its item's page, which is
    # where its openers and its saved answer live; a standalone one is its own
    # page.
    def title = subject&.try(:title).presence || tool.title
    def last_at = last_message&.created_at || run.created_at
  end

  def index
    @counts = chat_runs.group(:tool_slug).count
    @tool_slug = params[:tool].presence_in(@counts.keys)

    runs = chat_runs.then { |scope| @tool_slug ? scope.where(tool_slug: @tool_slug) : scope }
      .order(Arel.sql("(SELECT MAX(m.id) FROM tool_run_messages m WHERE m.tool_run_id = tool_runs.id) DESC"))
      .order(created_at: :desc)
      .limit(LIMIT)
      .includes(:subject)
      .to_a

    @conversations = decorate(runs)
    @truncated = @conversations.length == LIMIT
  end

  private
    def chat_runs
      Current.user.tool_runs.where(tool_slug: Tool.chat_slugs)
    end

    # Two queries for the whole page rather than two per row: the newest turn
    # of each run for the preview line, and how many turns it holds.
    def decorate(runs)
      ids = runs.map(&:id)
      newest = ToolRunMessage.where(tool_run_id: ids).conversational.group(:tool_run_id).maximum(:id)
      messages = ToolRunMessage.where(id: newest.values).index_by(&:tool_run_id)
      turns = ToolRunMessage.where(tool_run_id: ids).conversational.group(:tool_run_id).count

      runs.map do |run|
        Conversation.new(run: run, last_message: messages[run.id], turns: turns[run.id] || 0)
      end
    end
end
