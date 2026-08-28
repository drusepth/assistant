# Where a notification's one-tap link lands (D-decision-links). The whole
# point is that this page is ordinary: `require_authentication` runs here
# exactly as it does everywhere else, so an unauthenticated visitor gets the
# sign-in redirect and returns here afterwards, and a leaked or
# carrier-logged URL shows nobody anything.
#
# The token says *which* suggestions the notification was about. The session
# says whose they are — and the scope below is what makes a forged or
# borrowed token uninteresting: it can only ever name rows the signed-in
# user already owns.
class AgentDecisionsController < ApplicationController
  def show
    ids = Notifications::DecisionLink.suggestion_ids(params[:token])
    return redirect_to root_path, alert: "That link has expired — here's everything instead." if ids.nil?

    # Still-actionable only: a decision already made is not one to make
    # again, and showing it would invite a second click that does nothing.
    @suggestions = Current.user.suggestions.actionable.where(id: ids)
      .includes(:sections, :tool_run).order(:created_at)
  end
end
