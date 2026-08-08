module Admin
  # The one action in the app that destroys another member's items (D-household-reset).
  # Admin-gated like the rest of /admin, but with its own typed confirmation
  # and its own log line: everything else an admin can do is a read.
  class ResetsController < BaseController
    def create
      unless HouseholdReset.confirmed?(params[:confirmation])
        return redirect_to admin_root_path,
          alert: "Nothing was deleted — type #{HouseholdReset::CONFIRMATION} in the box to confirm."
      end

      household = Current.user.household
      Rails.logger.warn(
        "Household reset: \"#{household.name}\" (##{household.id}) by #{Current.user.email_address}"
      )
      summary = HouseholdReset.call(household)

      # The session went with the user; only the cookie is left to drop.
      cookies.delete(:session_id)
      Current.session = nil

      redirect_to next_stop, notice: cleared_message(summary)
    end

    private
      # A single-household instance is a fresh instance again and goes
      # straight to signup. On a box that still has other households, the
      # signup form is locked, so the sign-in page is the honest landing.
      def next_stop = User.exists? ? new_session_path : setup_path

      def cleared_message(summary)
        "Household cleared — #{helpers.pluralize(summary[:items], "item")} and " \
          "#{helpers.pluralize(summary[:members], "account")} deleted. Start over below."
      end
  end
end
