require "test_helper"

# The E3 dials: per-link mailbox settings and per-user digest preferences.
class MailSettingsTest < ActionDispatch::IntegrationTest
  setup { @account = linked_accounts(:alice_email) }

  test "mailbox dials persist sparsely and tighten polling when alerts turn on" do
    sign_in_as users(:one)

    patch settings_linked_account_path(@account), params: {
      digest: "1", alerts: "1", ai_processing: "0", paused: "0",
      mirror_window_days: "180", own_addresses: "one@example.com, alias@other.example"
    }
    assert_redirected_to settings_path

    @account.reload
    assert_equal true, @account.setting(:alerts)
    assert_equal false, @account.setting(:ai_processing)
    assert_equal 180, @account.setting(:mirror_window_days)
    assert_equal %w[ one@example.com alias@other.example ], @account.setting(:own_addresses)
    assert_equal 3.minutes, @account.sync_every, "alerts tighten the poll cadence"
  end

  test "another user's link settings are untouchable" do
    sign_in_as users(:two)

    patch settings_linked_account_path(@account), params: { alerts: "1" }
    assert_response :not_found
  end

  test "digest preferences save at the user level" do
    sign_in_as users(:one)

    patch mail_settings_path, params: { mail_digest_hour: "19", mail_digest_notify: "1" }
    assert_redirected_to settings_path

    users(:one).reload
    assert_equal 19, users(:one).mail_digest_hour
    assert users(:one).mail_digest_notify?
  end
end
