require "test_helper"

# D22: only Active sections notify, batched, counts/titles only, every
# channel failing independently.
class NotificationsTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "down") # digest half stays silent
  end

  test "a quiet section's suggestions never notify" do
    @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://ntfy.example/topic" })
    stub_request(:post, "https://ntfy.example/topic")

    perform_enqueued_jobs { AgentScanJob.perform_now(@user, cadence: "weekly") }

    assert_equal 1, @user.suggestions.count, "the suggestion still lands in-app"
    assert_not_requested :post, "https://ntfy.example/topic"
  end

  test "an active section's fresh suggestions fan out to webhook with titles only" do
    @user.user_sections.create!(section: sections(:health), agent_level: "active")
    @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://ntfy.example/topic" })
    stub_request(:post, "https://ntfy.example/topic")

    perform_enqueued_jobs { AgentScanJob.perform_now(@user, cadence: "daily") }

    assert_requested(:post, "https://ntfy.example/topic") do |request|
      payload = JSON.parse(request.body)
      payload["count"] == 1 &&
        payload["titles"] == [ "Book a health checkup" ] &&
        !request.body.include?("calendar in the last year") # titles, never bodies
    end
  end

  test "a rescan with nothing new sends nothing" do
    @user.user_sections.create!(section: sections(:health), agent_level: "active")
    @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://ntfy.example/topic" })
    delivered = stub_request(:post, "https://ntfy.example/topic")

    perform_enqueued_jobs { AgentScanJob.perform_now(@user, cadence: "daily") }
    perform_enqueued_jobs { AgentScanJob.perform_now(@user, cadence: "daily") }

    assert_requested delivered, times: 1
  end

  test "email channel delivers a titles-only mail" do
    with_instance_mail do
      @user.notification_channels.create!(kind: :email, config: { "address" => "alice@example.com" })

      assert_emails 1 do
        NotifyJob.perform_now(@user, [ "Book a health checkup" ])
      end
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "alice@example.com" ], mail.to
    assert_match "Book a health checkup", mail.body.to_s
  end

  test "a dead webhook fails silently and other channels still deliver" do
    with_instance_mail do
      @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://dead.example/hook" })
      @user.notification_channels.create!(kind: :email, config: { "address" => "alice@example.com" })
      stub_request(:post, "https://dead.example/hook").to_timeout

      assert_emails 1 do
        assert_nothing_raised { NotifyJob.perform_now(@user, [ "Something" ]) }
      end
    end
  end

  # D-instance-mail: an email channel can send through the user's own
  # linked mailbox, from them to them, with no instance SMTP at all.
  test "an email channel sends through the user's linked mailbox, from their own address" do
    mailbox = linked_accounts(:alice_email)
    @user.notification_channels.create!(kind: :email,
      config: { "address" => "one@example.com", "linked_account_id" => mailbox.id })

    assert_emails 1 do
      NotifyJob.perform_now(@user, [ "Renew the car registration" ])
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "one@example.com" ], mail.from
    assert_equal [ "one@example.com" ], mail.to
    assert_equal "smtp.example.com", mail.delivery_method.settings[:address]
    assert_equal "app-password", mail.delivery_method.settings[:password]
  end

  test "an email channel with nothing to send it is refused, not accepted and dropped" do
    channel = @user.notification_channels.new(kind: :email, config: { "address" => "alice@example.com" })

    assert_not channel.valid?
    assert_match "doesn't send email", channel.errors.full_messages.to_sentence
  end

  test "a mailbox channel whose sending was switched off later stays quiet and says why" do
    mailbox = linked_accounts(:alice_email)
    channel = @user.notification_channels.create!(kind: :email,
      config: { "address" => "one@example.com", "linked_account_id" => mailbox.id })
    mailbox.update!(disabled_scopes: [ "send" ])

    assert_emails 0 do
      assert_nothing_raised { NotifyJob.perform_now(@user, [ "Something" ]) }
    end
    assert_match "can't send: sending is switched off", channel.reload.label
  end

  test "an email channel made before the sender choice keeps using instance mail" do
    channel = with_instance_mail do
      @user.notification_channels.create!(kind: :email, config: { "address" => "alice@example.com" })
    end

    assert_emails 0 do
      NotifyJob.perform_now(@user, [ "Something" ])
    end
    assert_match "can't send: this server doesn't send email", channel.label
  end

  test "channel validations catch junk" do
    assert_not @user.notification_channels.new(kind: :webhook, config: { "url" => "ftp://nope" }).valid?
    assert_not @user.notification_channels.new(kind: :email, config: { "address" => "not-an-email" }).valid?
    assert_not @user.notification_channels.new(kind: :web_push, config: { "subscription" => { "endpoint" => "x" } }).valid?
    assert @user.notification_channels.new(kind: :web_push, config: {
      "subscription" => { "endpoint" => "https://push.example/x", "keys" => { "p256dh" => "k", "auth" => "a" } }
    }).valid?
  end

  test "settings adds an email channel through a linked mailbox, addressed to that mailbox by default" do
    sign_in = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in.post "/session", params: { email_address: @user.email_address, password: "password" }

    sign_in.post "/notification_channels", params: { kind: "email", address: "", sender: linked_accounts(:alice_email).id }

    channel = @user.notification_channels.sole
    assert_equal "one@example.com", channel.config["address"]
    assert_equal linked_accounts(:alice_email).id, channel.sending_account.id
  end

  test "channels are managed from settings" do
    sign_in = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in.post "/session", params: { email_address: @user.email_address, password: "password" }

    sign_in.post "/notification_channels", params: { kind: "webhook", url: "https://ntfy.example/topic" }
    channel = @user.notification_channels.sole
    assert_equal "webhook", channel.kind

    sign_in.delete "/notification_channels/#{channel.id}"
    assert_empty @user.notification_channels.reload
  end
end
