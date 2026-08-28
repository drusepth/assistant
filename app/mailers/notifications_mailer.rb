# Email is the last-resort channel (D22): only useful when the instance
# operator configured SMTP, never assumed. Delivery errors are swallowed
# by Notifications::Deliver.
class NotificationsMailer < ApplicationMailer
  def suggestions(address, summary, titles, link = nil)
    @summary = summary
    @titles = titles
    @link = link
    mail(to: address, subject: "Assistant: #{summary.truncate(70)}")
  end
end
