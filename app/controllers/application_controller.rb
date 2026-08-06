class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  default_form_builder ApplicationFormBuilder

  before_action :require_onboarding

  private
    # First-run flow (Q5): a signed-in user who hasn't onboarded lands in
    # /welcome. Controllers reachable before/without onboarding skip this.
    def require_onboarding
      return unless Current.user
      return if Current.user.onboarded_at

      redirect_to onboarding_path(step: 1)
    end
    def require_admin
      redirect_to settings_path, alert: "Only household admins can do that." unless Current.user.admin?
    end

    # Capture forms can send the browser back where capture happened (e.g.
    # the dashboard's inline quick-add panels) via a hidden return_to field.
    # Only local paths are honored.
    def return_to_path(fallback)
      path = params[:return_to].to_s
      path.start_with?("/") && !path.start_with?("//") ? path : fallback
    end
end
