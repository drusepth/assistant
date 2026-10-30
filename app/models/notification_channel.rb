# Where the agent may reach you off-app (D22). Five kinds, none assumed:
# webhook (ntfy/Home Assistant/Matrix — the self-hoster ecosystem), Web
# Push (per-instance VAPID, no third party), email (through your own
# linked mailbox, or the instance's SMTP if it has one — D-instance-mail),
# sms (D-sms-channels: your own modem via gammu-smsd, or a commodity
# carrier API), and signal (a signal-cli-rest-api container
# you run). Only Active-dial sections ever notify, batched per scan,
# counts and titles only — a lock screen is not private by default, and a
# carrier keeps a copy of everything besides.
class NotificationChannel < ApplicationRecord
  # SMS providers are first-party registry entries, not user data (D11):
  # adding one is an entry here plus a Notifications::Sms::* class. Fields
  # marked secret land in the encrypted `secrets` column; the rest stay in
  # plain `config` so Settings can render them back.
  SMS_PROVIDERS = {
    "gammu" => {
      label: "gammu-smsd (your own modem)",
      description: "A GSM modem and a SIM on your own box. No account, no per-message cost, " \
                   "nothing leaves the house but the text itself.",
      service: "Notifications::Sms::Gammu",
      fields: [
        { key: "outbox_path", label: "gammu-smsd outbox directory", placeholder: "/var/spool/gammu/outbox/",
          hint: "The OutboxPath from your gammu-smsdrc, readable and writable by this app." }
      ]
    },
    "twilio" => {
      label: "Twilio",
      description: "The commodity option. Needs an account, a number, and — for US traffic — " \
                   "A2P 10DLC registration before anything sends.",
      service: "Notifications::Sms::Twilio",
      fields: [
        { key: "account_sid", label: "Account SID", placeholder: "AC…" },
        { key: "auth_token", label: "Auth token", secret: true },
        { key: "from", label: "Send from", placeholder: "+15550001111",
          hint: "A number you own on Twilio, or a Messaging Service SID (MG…)." }
      ]
    },
    "sns" => {
      label: "Amazon SNS",
      description: "Publishes straight to a phone number — no number to rent, but the same " \
                   "US registration rules apply.",
      service: "Notifications::Sms::Sns",
      fields: [
        { key: "region", label: "Region", placeholder: "us-east-1" },
        { key: "access_key_id", label: "Access key ID", secret: true },
        { key: "secret_access_key", label: "Secret access key", secret: true },
        { key: "sender_id", label: "Sender ID", optional: true,
          hint: "Ignored in the US and Canada; some countries show it instead of a number." }
      ]
    }
  }.freeze

  # SMS is the first channel that costs real money per message, so it is
  # metered. A watcher loop should cost a user a few cents, not a bill.
  DAILY_LIMIT_DEFAULT = 10

  # Two GSM segments. Titles are short by construction (D22), but a long
  # one must not quietly cost four messages.
  TEXT_LIMIT = 300

  belongs_to :user

  enum :kind, { webhook: "webhook", web_push: "web_push", email: "email", sms: "sms", signal: "signal" }

  # Encrypted at rest; serialize must come first so encryption wraps the
  # JSON coder (hash in Ruby, ciphertext in the file) — same shape as
  # linked_accounts.credentials.
  serialize :secrets, coder: JSON
  encrypts :secrets

  before_validation :normalize_numbers

  validates :config, presence: true
  validate :config_shape

  scope :active, -> { where(enabled: true) }

  def label
    case kind
    when "webhook" then "Webhook — #{config["url"].to_s.truncate(60)}"
    when "web_push" then "Browser push — added #{created_at.strftime("%b %-d, %Y")}"
    when "email" then email_label
    when "sms" then "Text message — #{config["to"]} via #{sms_provider_settings[:label]}"
    when "signal" then "Signal — #{config["to"]}"
    end
  end

  # Email goes out one of two ways (D-instance-mail): through a mailbox the
  # user linked, from them to them, which no spam filter doubts; or through
  # the instance's own SMTP. A channel with no linked_account_id is the
  # second kind, which is also what every channel made before the choice
  # existed means.
  def sends_through_mailbox? = email? && config["linked_account_id"].present?

  def sending_account
    return nil unless sends_through_mailbox?

    user.linked_accounts.find_by(id: config["linked_account_id"], provider: "email")
  end

  # Why this channel can't send right now, in words for Settings and the
  # log — or nil when it can. Checked at send time as well as at creation,
  # because the mailbox link or the server's SMTP can go away later.
  def email_sender_problem
    return nil unless email?

    if sends_through_mailbox?
      account = sending_account
      return "its mailbox link was removed" if account.nil?
      return "sending is switched off on #{account.display_name}" unless account.sends_mail?
    elsif !InstanceMail.configured?
      return "this server doesn't send email"
    end
    nil
  end

  def sms_provider = config["provider"].to_s

  # Unknown providers fail validation; fall back so the rest of the
  # validations can still run without raising.
  def sms_provider_settings = SMS_PROVIDERS.fetch(sms_provider) { { label: sms_provider, fields: [] } }

  # The credential half, whichever column it happens to live in — provider
  # classes should never care which.
  def setting(key) = secrets.to_h[key.to_s].presence || config[key.to_s].presence

  # Only metered kinds have a ceiling; everything else returns nil.
  def daily_limit
    limit = config["daily_limit"]
    return limit.to_i if limit.present?

    DAILY_LIMIT_DEFAULT if sms?
  end

  def over_daily_limit?
    return false if daily_limit.nil?

    sent_on == Date.current && sent_count >= daily_limit
  end

  # Counted after a send succeeds, so a provider outage doesn't eat the
  # day's budget. Two jobs racing can overshoot by one; a cap this coarse
  # doesn't warrant a lock.
  def record_send!
    if sent_on == Date.current
      update_columns(sent_count: sent_count + 1)
    else
      update_columns(sent_on: Date.current, sent_count: 1)
    end
  end

  private
    def email_label
      via = sends_through_mailbox? && sending_account ? ", from your #{sending_account.label} mailbox" : ""
      problem = email_sender_problem
      "Email — #{config["address"]}#{via}#{" (can't send: #{problem})" if problem}"
    end

    # Numbers arrive through the phone mask as "(503) 555-0142" or pasted
    # with any decoration; carriers want E.164, so it's settled once here
    # rather than in three provider classes — by the same PhoneNumber every
    # contact uses, so ten bare digits get their +1 instead of becoming a
    # number in another country.
    def normalize_numbers
      return unless sms? || signal?

      %w[ to from ].each do |key|
        value = config[key].to_s.strip
        next if value.blank?
        # Not everything in a "from" is a number — a Twilio Messaging
        # Service SID (MG…) lives there too, and stripping it to digits
        # would quietly turn it into a wrong phone number.
        next if value.match?(/[A-Za-z]/)

        config[key] = PhoneNumber.normalize(value)
      end
    end

    def config_shape
      case kind
      when "webhook"
        url = config["url"].to_s
        errors.add(:base, "Webhook needs an http(s) URL.") unless url.start_with?("http://", "https://")
      when "web_push"
        subscription = config["subscription"] || {}
        unless subscription["endpoint"].present? && subscription.dig("keys", "p256dh").present? && subscription.dig("keys", "auth").present?
          errors.add(:base, "That browser subscription looks incomplete — try enabling push again.")
        end
      when "email"
        errors.add(:base, "Email needs an address.") unless config["address"].to_s.include?("@")
        # Only a new channel is refused: one that loses its sender later
        # stays listed with the reason, rather than failing every save.
        if new_record? && (problem = email_sender_problem)
          errors.add(:base, "Email can't be sent: #{problem}.")
        end
      when "sms" then validate_sms
      when "signal" then validate_signal
      end
    end

    def validate_sms
      unless SMS_PROVIDERS.key?(sms_provider)
        errors.add(:base, "Pick an SMS provider.")
        return
      end

      validate_phone(config["to"], "The number to text")
      sms_provider_settings[:fields].each do |field|
        next if field[:optional]
        next if setting(field[:key]).present?

        errors.add(:base, "#{sms_provider_settings[:label]} needs #{field[:label]}.")
      end
    end

    def validate_signal
      url = config["url"].to_s
      errors.add(:base, "Signal needs the URL of your signal-cli-rest-api.") unless url.start_with?("http://", "https://")
      validate_phone(config["from"], "The Signal number to send from")
      validate_phone(config["to"], "The number to message")
    end

    # A number PhoneNumber couldn't read is left as typed, so anything that
    # isn't "+" and digits by now is refused rather than texted.
    def validate_phone(value, subject)
      errors.add(:base, "#{subject} must be a phone number in +country-code form.") unless value.to_s.match?(/\A\+[0-9]{7,15}\z/)
    end
end
