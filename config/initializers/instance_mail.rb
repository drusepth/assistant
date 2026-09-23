# Optional outgoing mail from ENV (D-instance-mail; docs/MAIL.md). Applied
# in to_prepare so the autoloaded InstanceMail is available, and after
# ActionMailer has copied config.action_mailer onto its base class.
Rails.application.config.to_prepare do
  InstanceMail.apply!
end
