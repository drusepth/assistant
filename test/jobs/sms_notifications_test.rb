require "test_helper"

# D-sms-channels: the phone channels. Same D22 payload rule as every other
# channel (counts and titles, never bodies), plus the two things only these
# have — credentials that must not sit in plaintext, and a per-message cost
# that must not run away.
class SmsNotificationsTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @titles = [ "Book a health checkup" ]
  end

  # --- gammu ----------------------------------------------------------

  test "gammu drops a file into the outbox in the FILES backend's name format" do
    outbox = Dir.mktmpdir
    channel_for(:gammu, outbox_path: outbox)

    NotifyJob.perform_now(@user, @titles)

    written = Dir.children(outbox)
    assert_equal 1, written.size, "one message, one file"
    name = written.sole
    assert_match(/\AOUTG\d{8}_\d{6}_\d{6}_\+15555550123_assistant\.txt\z/, name)
    assert_match "Book a health checkup", File.read(File.join(outbox, name))
  end

  test "gammu leaves no staging file behind for the daemon to trip over" do
    outbox = Dir.mktmpdir
    channel_for(:gammu, outbox_path: outbox)

    NotifyJob.perform_now(@user, @titles)

    assert_empty Dir.children(outbox).grep(/\.tmp\z/), "the staged write is renamed, not left"
  end

  test "an unwritable gammu outbox fails loudly in the log, not silently" do
    channel_for(:gammu, outbox_path: "/nonexistent/outbox")

    assert_nothing_raised { NotifyJob.perform_now(@user, @titles) }
  end

  # --- twilio ---------------------------------------------------------

  test "twilio posts a form with basic auth and titles only" do
    channel_for(:twilio, account_sid: "AC123", auth_token: "secret-token", from: "+15550001111")
    endpoint = "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json"
    stub_request(:post, endpoint)

    NotifyJob.perform_now(@user, @titles)

    assert_requested(:post, endpoint) do |request|
      form = URI.decode_www_form(request.body).to_h
      assert_equal "+15555550123", form["To"]
      assert_equal "+15550001111", form["From"]
      assert_match "Book a health checkup", form["Body"]
      assert_equal "Basic #{Base64.strict_encode64("AC123:secret-token")}", request.headers["Authorization"]
    end
  end

  test "a messaging service SID goes in its own field, not From" do
    channel_for(:twilio, account_sid: "AC123", auth_token: "t", from: "MG9999")
    endpoint = "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json"
    stub_request(:post, endpoint)

    NotifyJob.perform_now(@user, @titles)

    assert_requested(:post, endpoint) do |request|
      form = URI.decode_www_form(request.body).to_h
      form["MessagingServiceSid"] == "MG9999" && form["From"].nil?
    end
  end

  # --- sns ------------------------------------------------------------

  test "sns publishes to the region with a v4 signature over the sent body" do
    channel_for(:sns, region: "us-east-1", access_key_id: "AKIA1", secret_access_key: "shh")
    stub_request(:post, "https://sns.us-east-1.amazonaws.com/")

    NotifyJob.perform_now(@user, @titles)

    assert_requested(:post, "https://sns.us-east-1.amazonaws.com/") do |request|
      form = URI.decode_www_form(request.body).to_h
      assert_equal "Publish", form["Action"]
      assert_equal "+15555550123", form["PhoneNumber"]
      assert_equal "Transactional", form["MessageAttributes.entry.1.Value.StringValue"]

      authorization = request.headers["Authorization"]
      assert_match %r{\AAWS4-HMAC-SHA256 Credential=AKIA1/\d{8}/us-east-1/sns/aws4_request}, authorization
      assert_match "SignedHeaders=content-type;host;x-amz-date", authorization
      assert_match(/Signature=[0-9a-f]{64}\z/, authorization)
      assert_not_includes authorization, "shh", "the secret signs the request, it never travels with it"
    end
  end

  # --- signal ---------------------------------------------------------

  test "signal posts to v2/send, preserving a path prefix on the base URL" do
    @user.notification_channels.create!(kind: :signal, config: {
      "url" => "http://signal.example/api/", "from" => "+15550001111", "to" => "+15555550123"
    })
    stub_request(:post, "http://signal.example/api/v2/send")

    NotifyJob.perform_now(@user, @titles)

    assert_requested(:post, "http://signal.example/api/v2/send") do |request|
      payload = JSON.parse(request.body)
      payload["number"] == "+15550001111" &&
        payload["recipients"] == [ "+15555550123" ] &&
        payload["message"].include?("Book a health checkup")
    end
  end

  test "signal uses basic auth only when credentials were configured" do
    @user.notification_channels.create!(
      kind: :signal,
      config: { "url" => "http://signal.example", "from" => "+15550001111", "to" => "+15555550123" },
      secrets: { "username" => "u", "password" => "p" }
    )
    stub_request(:post, "http://signal.example/v2/send")

    NotifyJob.perform_now(@user, @titles)

    assert_requested(:post, "http://signal.example/v2/send",
      headers: { "Authorization" => "Basic #{Base64.strict_encode64("u:p")}" })
  end

  # --- the rules that only apply to a phone ---------------------------

  test "credentials are encrypted at rest" do
    channel = channel_for(:twilio, account_sid: "AC123", auth_token: "secret-token", from: "+15550001111")

    stored = NotificationChannel.connection.select_value(
      "SELECT secrets FROM notification_channels WHERE id = #{channel.id}"
    )
    assert_not_includes stored.to_s, "secret-token"
    assert_equal "secret-token", channel.reload.setting("auth_token")
  end

  test "the daily cap stops sending and does not count failed attempts" do
    outbox = Dir.mktmpdir
    channel = channel_for(:gammu, outbox_path: outbox, daily_limit: 2)

    3.times { NotifyJob.perform_now(@user, @titles) }

    assert_equal 2, Dir.children(outbox).size, "the third send is over the cap"
    assert_equal 2, channel.reload.sent_count
  end

  test "the cap resets on a new day" do
    outbox = Dir.mktmpdir
    channel = channel_for(:gammu, outbox_path: outbox, daily_limit: 1)
    NotifyJob.perform_now(@user, @titles)
    channel.update_columns(sent_on: Date.yesterday, sent_count: 99)

    NotifyJob.perform_now(@user, @titles)

    assert_equal Date.current, channel.reload.sent_on
    assert_equal 1, channel.sent_count
  end

  test "a long batch is truncated to bound what a text costs" do
    outbox = Dir.mktmpdir
    channel_for(:gammu, outbox_path: outbox)

    NotifyJob.perform_now(@user, Array.new(40) { |i| "A rather long suggestion title number #{i}" })

    text = File.read(File.join(outbox, Dir.children(outbox).sole))
    assert_operator text.length, :<=, NotificationChannel::TEXT_LIMIT
  end

  test "the decision link rides inside the same length bound, whole" do
    # D-decision-links spends from the D-sms-channels budget rather than
    # extending it: the bound caps what a carrier keeps and what a message
    # costs, and neither cares which half of the text is a URL. A truncated
    # URL, though, is worse than no URL — so the summary yields, not the link.
    outbox = Dir.mktmpdir
    channel_for(:gammu, outbox_path: outbox)
    suggestion = @user.suggestions.create!(watcher_slug: "checkup_cadence",
      fingerprint: "checkup_cadence/x", title: "Book a dental cleaning")

    NotifyJob.perform_now(@user, Array.new(40) { |i| "A rather long suggestion title number #{i}" },
      suggestion_ids: [ suggestion.id ])

    text = File.read(File.join(outbox, Dir.children(outbox).sole))
    assert_operator text.length, :<=, NotificationChannel::TEXT_LIMIT
    token = text[%r{/assistant/decisions/([A-Za-z0-9_\-.=]+)\z}, 1]
    assert_equal [ suggestion.id ], Notifications::DecisionLink.suggestion_ids(token),
      "the URL arrived whole enough to still open the right batch"
  end

  test "one broken phone channel never silences the others" do
    outbox = Dir.mktmpdir
    channel_for(:gammu, outbox_path: outbox)
    channel_for(:twilio, account_sid: "AC123", auth_token: "t", from: "+15550001111")
    stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json")
      .to_return(status: 401, body: "bad credentials")

    assert_nothing_raised { NotifyJob.perform_now(@user, @titles) }

    assert_equal 1, Dir.children(outbox).size, "the modem still sent"
  end

  # --- validation -----------------------------------------------------

  test "channel validations catch junk" do
    assert_not @user.notification_channels.new(kind: :sms, config: { "provider" => "nope", "to" => "+15555550123" }).valid?
    assert_not @user.notification_channels.new(kind: :sms, config: { "provider" => "gammu", "to" => "" }).valid?,
      "a provider without a destination is not a channel"
    assert_not @user.notification_channels.new(kind: :sms, config: { "provider" => "gammu", "to" => "+15555550123" }).valid?,
      "gammu needs its outbox path"
    assert_not @user.notification_channels.new(kind: :signal, config: {
      "url" => "not-a-url", "from" => "+15550001111", "to" => "+15555550123"
    }).valid?
  end

  test "numbers survive being pasted with the decoration people paste" do
    channel = @user.notification_channels.create!(kind: :sms, config: {
      "provider" => "gammu", "outbox_path" => "/tmp", "to" => "+1 (555) 555-0123"
    })

    assert_equal "+15555550123", channel.config["to"]
  end

  test "a Twilio channel is added from settings with the token kept out of config" do
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post "/session", params: { email_address: @user.email_address, password: "password" }

    session.post "/notification_channels", params: {
      kind: "sms", provider: "twilio", to: "+15555550123", daily_limit: "5",
      provider_fields: { twilio: { account_sid: "AC123", auth_token: "secret-token", from: "+15550001111" } }
    }

    channel = @user.notification_channels.sole
    assert_equal "twilio", channel.sms_provider
    assert_equal 5, channel.daily_limit
    assert_equal "secret-token", channel.setting("auth_token")
    assert_not_includes channel.config.to_s, "secret-token", "secrets never land in plain config"
  end

  private
    def channel_for(provider, daily_limit: nil, **fields)
      settings = NotificationChannel::SMS_PROVIDERS.fetch(provider.to_s)
      secret_keys = settings[:fields].select { |field| field[:secret] }.map { |field| field[:key] }

      config = { "provider" => provider.to_s, "to" => "+15555550123" }
      config["daily_limit"] = daily_limit if daily_limit
      secrets = {}
      fields.each do |key, value|
        (secret_keys.include?(key.to_s) ? secrets : config)[key.to_s] = value
      end

      @user.notification_channels.create!(kind: :sms, config: config, secrets: secrets)
    end
end
