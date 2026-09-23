class NotificationChannelsController < ApplicationController
  # A test reaches out to a carrier or someone's server on every click; a
  # stuck finger shouldn't become a bill or a flood.
  rate_limit to: 5, within: 1.minute, only: :send_test,
    with: -> { redirect_to settings_path, alert: "Too many tests at once — try again in a minute." }

  def create
    channel = Current.user.notification_channels.new(channel_attributes)

    respond_to do |format|
      if channel.save
        format.html { redirect_to settings_path, notice: "Notification channel added." }
        format.json { head :created }
      else
        format.html { redirect_to settings_path, alert: channel.errors.full_messages.to_sentence }
        format.json { render json: { errors: channel.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    Current.user.notification_channels.find(params[:id]).destroy!
    redirect_to settings_path, notice: "Notification channel removed."
  end

  # Sends one test message through this channel right now, so a mistyped
  # topic or a stale token shows up here rather than as a silence the day
  # something real needed saying.
  def send_test
    channel = Current.user.notification_channels.find(params[:id])

    begin
      Notifications::Deliver.test!(channel)
    rescue StandardError => error
      Rails.logger.warn("notification test #{channel.kind}##{channel.id} failed: #{error.class}: #{error.message}")
      return redirect_to settings_path, alert: "Test failed: #{test_failure_message(error)}"
    end

    redirect_to settings_path, notice: "Test sent to #{channel.label}. If it doesn't arrive, check that channel's setup."
  end

  private
    # A DeliveryError is already written for the user; anything else (a
    # timeout, a refused connection, an SMTP error) gets its class named so
    # there's something to search for.
    def test_failure_message(error)
      error.is_a?(Notifications::DeliveryError) ? error.message : "#{error.class.name.demodulize} — #{error.message}".truncate(200)
    end

    def channel_attributes
      case params.expect(:kind)
      when "webhook" then { kind: :webhook, config: { "url" => params[:url].to_s.strip } }
      when "email" then email_attributes
      when "web_push" then { kind: :web_push, config: { "subscription" => subscription_params } }
      when "sms" then sms_attributes
      when "signal" then signal_attributes
      else raise ActionController::BadRequest, "unknown channel kind"
      end
    end

    # `sender` is a linked mailbox id, or "instance" / blank for the
    # server's own SMTP (D-instance-mail). A mailbox with no address given
    # sends to itself, which is the usual wish.
    def email_attributes
      config = { "address" => params[:address].to_s.strip }
      sender = params[:sender].to_s

      if sender.present? && sender != "instance"
        account = Current.user.linked_accounts.find_by(id: sender, provider: "email")
        raise ActionController::BadRequest, "unknown mailbox" if account.nil?

        config["linked_account_id"] = account.id
        config["address"] = account.email_address if config["address"].blank?
      end

      { kind: :email, config: config }
    end

    def subscription_params
      params.expect(subscription: [ :endpoint, keys: %i[ p256dh auth ] ]).to_h
    end

    # The registry decides which fields exist and which of them are secret
    # (D-sms-channels), so adding a provider never touches this controller.
    # Every provider's fields are submitted together; only the selected
    # one's are read, which is also what keeps an abandoned auth token from
    # being stored.
    def sms_attributes
      provider = params[:provider].to_s
      settings = NotificationChannel::SMS_PROVIDERS[provider]
      raise ActionController::BadRequest, "unknown SMS provider" if settings.nil?

      config = { "provider" => provider, "to" => params[:to].to_s.strip }
      config["daily_limit"] = params[:daily_limit].to_i if params[:daily_limit].present?
      secrets = {}

      settings[:fields].each do |field|
        value = params.dig(:provider_fields, provider, field[:key]).to_s.strip
        next if value.blank?

        (field[:secret] ? secrets : config)[field[:key]] = value
      end

      { kind: :sms, config: config, secrets: secrets }
    end

    def signal_attributes
      config = {
        "url" => params[:url].to_s.strip,
        "from" => params[:from].to_s.strip,
        "to" => params[:to].to_s.strip
      }
      config["daily_limit"] = params[:daily_limit].to_i if params[:daily_limit].present?

      secrets = {}
      secrets["username"] = params[:username].to_s.strip if params[:username].present?
      secrets["password"] = params[:password].to_s if params[:password].present?

      { kind: :signal, config: config, secrets: secrets }
    end
end
