class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  default_form_builder ApplicationFormBuilder

  before_action :require_onboarding
  around_action :use_household_time_zone

  private
    # One instance serves one household, so its zone is the app's zone
    # (D-household-profile). Without this everything dated runs in UTC and
    # "due today" flips over in the middle of the evening for most of the
    # planet. Blank keeps the instance default.
    def use_household_time_zone(&block)
      zone = Current.user&.household&.zone || Time.zone
      Time.use_zone(zone, &block)
    end

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
