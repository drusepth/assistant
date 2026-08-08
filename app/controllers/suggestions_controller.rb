class SuggestionsController < ApplicationController
  before_action :set_suggestion

  def accept
    if (tool = @suggestion.tool_action)
      @suggestion.accept!
      redirect_to new_tool_run_path(tool["slug"], inputs: tool["inputs"] || {})
    elsif (path = @suggestion.path_action)
      @suggestion.accept!
      redirect_to path
    else
      created = @suggestion.accept!
      redirect_back fallback_location: root_path, notice: @suggestion.accept_notice(created)
    end
  end

  def dismiss
    @suggestion.dismiss!
    redirect_back fallback_location: root_path
  end

  def snooze
    @suggestion.snooze!
    redirect_back fallback_location: root_path, notice: "Snoozed for two weeks."
  end

  private
    # Suggestions are personal: only their owner ever sees or acts on them.
    def set_suggestion
      @suggestion = Current.user.suggestions.find(params[:id])
    end
end
