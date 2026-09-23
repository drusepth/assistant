class ApplicationMailer < ActionMailer::Base
  default from: -> { InstanceMail.from }
  layout "mailer"
end
