require "test_helper"

# The Settings "Send test" button: one message, one channel, sent now, with
# the outcome said on the page rather than only in the log.
class NotificationChannelTestsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
    post session_path, params: { email_address: @user.email_address, password: "password" }
  end

  test "a working webhook gets the test message and the page says it was sent" do
    channel = @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://ntfy.example/topic" })
    stub_request(:post, "https://ntfy.example/topic")

    post send_test_notification_channel_path(channel)

    assert_redirected_to settings_path
    assert_match "Test sent", flash[:notice]
    assert_requested(:post, "https://ntfy.example/topic") do |request|
      JSON.parse(request.body)["message"] == Notifications::Deliver::TEST_SUMMARY
    end
  end

  test "a webhook that answers an error is reported, not called a success" do
    channel = @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://ntfy.example/typo" })
    stub_request(:post, "https://ntfy.example/typo").to_return(status: 404)

    post send_test_notification_channel_path(channel)

    assert_redirected_to settings_path
    assert_equal "Test failed: ntfy.example answered 404", flash[:alert]
  end

  test "an unreachable webhook is reported by name" do
    channel = @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://dead.example/hook" })
    stub_request(:post, "https://dead.example/hook").to_timeout

    post send_test_notification_channel_path(channel)

    assert_match(/\ATest failed: /, flash[:alert])
  end

  test "an email channel sends the test mail" do
    with_instance_mail do
      channel = @user.notification_channels.create!(kind: :email, config: { "address" => "alice@example.com" })

      assert_emails 1 do
        post send_test_notification_channel_path(channel)
      end
    end

    assert_equal [ "alice@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "an email channel that lost its sender says why" do
    channel = with_instance_mail do
      @user.notification_channels.create!(kind: :email, config: { "address" => "alice@example.com" })
    end

    post send_test_notification_channel_path(channel)

    assert_equal "Test failed: this server doesn't send email", flash[:alert]
  end

  test "a metered channel's test counts toward its cap and is refused once the cap is spent" do
    outbox = Dir.mktmpdir
    channel = @user.notification_channels.create!(kind: :sms,
      config: { "provider" => "gammu", "to" => "+15035550100", "outbox_path" => outbox, "daily_limit" => 1 })

    post send_test_notification_channel_path(channel)
    assert_equal 1, Dir.children(outbox).size
    assert_equal 1, channel.reload.sent_count

    post send_test_notification_channel_path(channel)
    assert_equal 1, Dir.children(outbox).size
    assert_match "already sent its 1 messages for today", flash[:alert]
  end

  test "someone else's channel can't be tested" do
    channel = users(:two).notification_channels.create!(kind: :webhook, config: { "url" => "https://ntfy.example/theirs" })

    post send_test_notification_channel_path(channel)

    assert_response :not_found
  end
end
