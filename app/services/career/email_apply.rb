module Career
  # Ask-then-send, email only (D-career-web): carries an application the user just
  # reviewed and edited out through THEIR linked mailbox — their address,
  # their SMTP server, their explicit click. The compose form is the ask;
  # this only delivers it. Deliberately narrow: no ATS form automation, no
  # sending the app initiates on its own.
  class EmailApply
    class Error < StandardError; end

    # Tests flip this to :test to capture instead of connecting.
    cattr_accessor :delivery_override, default: nil

    def initialize(user:, to:, subject:, body:, resume: nil)
      @user = user
      @to = to.to_s.strip
      @subject = subject.to_s.strip
      @body = body.to_s
      @resume = resume
    end

    def call
      raise Error, "Who is it going to? The recipient is blank." if @to.blank? || !@to.include?("@")
      raise Error, "The message body is blank — nothing to send." if @body.strip.blank?

      mail = build_mail
      mail.delivery_method(self.class.delivery_override || :smtp, smtp_settings)
      mail.deliver!
      mail
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "Sending failed (#{e.message.to_s.truncate(120)}) — check the SMTP details on your email link."
    end

    private
      def account
        @account ||= begin
          account = @user.linked_accounts.find_by(provider: "email")
          raise Error, "Link your email in Settings first — applications send from your address, never the app's." unless account
          raise Error, "Sending is switched off for your email link (Settings → Connected accounts)." unless account.allows?("send")

          account
        end
      end

      def credentials = account.credentials

      def build_mail
        mail = Mail.new
        mail.from = credentials["username"]
        mail.to = @to
        mail.subject = @subject.presence || "Job application"
        mail.body = @body
        if @resume&.file&.attached?
          mail.add_file(filename: @resume.file.filename.to_s, content: @resume.file.download)
        end
        mail
      end

      def smtp_settings
        raise Error, "No SMTP server on your email link — add one in Settings → Connected accounts." if account.smtp_host.blank?

        account.smtp_settings
      end
  end
end
