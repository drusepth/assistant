# The instance's own outgoing mail (D-instance-mail): optional, any
# provider, configured by the operator in ENV and never assumed.
#
# Nothing in the app depends on it. Invitations and password resets work
# by copied links (D15), notifications have four other channels (D22), and
# a user's email channel can send through their own linked mailbox instead.
# What this buys is convenience: the "email me a reset link" form, and an
# email channel for people who never link a mailbox.
#
# Sending without a relay was considered and rejected: home connections
# block port 25, residential addresses are on the blocklists every large
# provider consults, and Gmail and Yahoo refuse unauthenticated mail
# outright. The result is not "lands in spam", it is "never arrives".
#
# Unset means off, and every surface that would send says so rather than
# pretending (the password form, the email channel picker).
module InstanceMail
  class << self
    def configured? = address.present?

    # A reset email is only worth sending when the link inside it points
    # somewhere real (AppHost), and never at a host a request made up.
    def password_resets? = configured? && AppHost.known?

    def address = ENV["SMTP_ADDRESS"].presence

    def port = ENV.fetch("SMTP_PORT", "587").to_i

    # SMTP_FROM wins; a username that is already an address is the next
    # best guess (Gmail, Fastmail, most ISPs send as the account); the
    # instance's own host is the last resort.
    def from
      ENV["SMTP_FROM"].presence ||
        (ENV["SMTP_USERNAME"] if ENV["SMTP_USERNAME"].to_s.include?("@")) ||
        "assistant@#{AppHost.host&.split(":")&.first.presence || "localhost"}"
    end

    # Port 465 speaks TLS from the first byte; everything else (587, 25,
    # 2525) starts plain and upgrades with STARTTLS when offered.
    def smtp_settings
      username = ENV["SMTP_USERNAME"].presence
      {
        address: address,
        port: port,
        domain: ENV["SMTP_DOMAIN"].presence,
        user_name: username,
        password: ENV["SMTP_PASSWORD"].presence,
        authentication: (ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym if username),
        tls: port == 465,
        enable_starttls_auto: port != 465
      }.compact
    end

    # Called at boot (config/initializers/instance_mail.rb). Test keeps its
    # :test delivery no matter what the ENV says.
    def apply!(base = ActionMailer::Base, env: Rails.env)
      return if env.test? || !configured?

      base.delivery_method = :smtp
      base.smtp_settings = smtp_settings
    end
  end
end
