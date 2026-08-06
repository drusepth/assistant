# The user disposes (D20): three verbs on a suggestion, all explicit
# clicks. Accept materializes the payload (or hands off to a prefilled tool
# form via the D21 machinery); snooze and dismiss just quiet it.
class SuggestionsController < ApplicationController
  before_action :set_suggestion

  def accept
    @suggestion.accept!

    if (tool = @suggestion.routed_tool)
      redirect_to new_tool_run_path(tool.slug, inputs: @suggestion.action["inputs"] || {})
    else
      redirect_back fallback_location: root_path, notice: accept_notice
    end
  end

  def dismiss
    @suggestion.dismiss!
    redirect_back fallback_location: root_path
  end

  def snooze
    @suggestion.snooze!
    redirect_back fallback_location: root_path, notice: "Snoozed for a week."
  end

  private
    def set_suggestion
      @suggestion = Current.user.suggestions.find(params[:id])
    end

    def accept_notice
      case @suggestion.action_type
      when "create_event" then "Added to your calendar."
      when "create_task" then "Added to your tasks."
      else "Got it."
      end
    end
end
