# The user's side of the D20 contract: the agent proposed, they dispose.
# Only pending suggestions can be acted on — a second click 404s instead of
# double-performing.
class SuggestionsController < ApplicationController
  before_action :set_suggestion

  def accept
    item = @suggestion.accept!
    redirect_back fallback_location: root_path, notice: "“#{item.title}” is on your calendar."
  end

  def dismiss
    @suggestion.dismiss!
    redirect_back fallback_location: root_path, notice: "Okay — won't bring that one up again."
  end

  def snooze
    @suggestion.snooze!
    redirect_back fallback_location: root_path, notice: "Snoozed for a week."
  end

  private
    def set_suggestion
      @suggestion = Current.user.suggestions.pending.find(params[:id])
    end
end
