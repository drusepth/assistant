# Email is one channel among five (D22), and never assumed: it sends
# through the user's own linked mailbox when the channel names one, or
# through the instance's SMTP when the operator configured it
# (D-instance-mail). Delivery errors are swallowed by Notifications::Deliver.
class NotificationsMailer < ApplicationMailer
  # sender: a LinkedAccount to send through, or nil for the instance's own
  # mail. Its settings ride on the message rather than the class, so one
  # user's mailbox never becomes anyone else's sender.
  def suggestions(address, summary, titles, link = nil, sender: nil)
    @summary = summary
    @titles = titles
    @link = link

    headers = { to: address, subject: "Assistant: #{summary.truncate(70)}" }
    headers.merge!(from: sender.email_address, delivery_method_options: sender.smtp_settings) if sender
    mail(**headers)
  end
end
