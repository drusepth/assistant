# The address this instance answers at, for links built where there is no
# request to ask: a job, a mailer, a rake task (D-decision-links,
# D-instance-mail).
#
# Self-hosted instances live at whatever address their operator gave them,
# and the app cannot know it from inside a job. APP_HOST is that answer
# ("assistant.example.org", or with a scheme and port). Without it there is
# simply no link — a wrong URL in a text message or an email is worse than
# none. A request's own Host header is never used for this: letting a
# stranger's header decide where a password reset link points is the
# classic reset-poisoning hole.
module AppHost
  class << self
    def host
      configured = ENV["APP_HOST"].presence || mailer_host
      configured&.sub(%r{\Ahttps?://}, "")&.chomp("/")
    end

    def known? = host.present?

    # For url helpers: `edit_password_url(token, **AppHost.url_options)`.
    def url_options
      return {} unless known?

      scheme = ENV["APP_HOST"].to_s.start_with?("http://") || host.start_with?("localhost") ? "http" : "https"
      { host: host, protocol: scheme }
    end

    private
      # In development and test the mailer host is already the real one.
      # In production Rails ships "example.com" as a placeholder, and
      # sending somebody a link to a domain we don't own is worse than
      # sending no link — so there, only a deliberate APP_HOST counts.
      def mailer_host
        options = Rails.application.config.action_mailer.default_url_options || {}
        host = options[:host]
        return nil if host.blank?
        return nil if Rails.env.production? && host == "example.com"

        options[:port] ? "#{host}:#{options[:port]}" : host
      end
  end
end
