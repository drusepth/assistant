# User-level mail preferences (EMAIL_PLAN.md §7): when the daily digest
# arrives and whether it pings the notification channels. Per-link dials
# live on the linked account (LinkedAccountsController#update_settings).
class MailSettingsController < ApplicationController
  def update
    hour = params[:mail_digest_hour].to_i.clamp(0, 23)
    Current.user.update!(mail_digest_hour: hour, mail_digest_notify: params[:mail_digest_notify] == "1")
    redirect_to settings_path, notice: "Mail digest preferences saved."
  end
end
