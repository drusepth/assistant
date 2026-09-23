require "test_helper"

# D-instance-mail: optional, any provider, from ENV; off means off.
class InstanceMailTest < ActiveSupport::TestCase
  SMTP_KEYS = %w[ SMTP_ADDRESS SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_FROM SMTP_DOMAIN SMTP_AUTHENTICATION APP_HOST ].freeze

  setup { @saved = SMTP_KEYS.index_with { |key| ENV[key] } }
  teardown { @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value } }

  test "unset means off" do
    SMTP_KEYS.each { |key| ENV.delete(key) }

    assert_not InstanceMail.configured?
    assert_not InstanceMail.password_resets?
  end

  test "a submission-port provider gets STARTTLS and plain auth" do
    ENV["SMTP_ADDRESS"] = "smtp.fastmail.com"
    ENV["SMTP_USERNAME"] = "me@fastmail.com"
    ENV["SMTP_PASSWORD"] = "app-password"

    settings = InstanceMail.smtp_settings
    assert_equal 587, settings[:port]
    assert settings[:enable_starttls_auto]
    assert_not settings[:tls]
    assert_equal :plain, settings[:authentication]
    assert_equal "me@fastmail.com", InstanceMail.from
  end

  test "port 465 speaks TLS from the first byte" do
    ENV["SMTP_ADDRESS"] = "smtp.example.com"
    ENV["SMTP_PORT"] = "465"

    settings = InstanceMail.smtp_settings
    assert settings[:tls]
    assert_not settings[:enable_starttls_auto]
  end

  test "an unauthenticated relay sends no auth at all" do
    ENV["SMTP_ADDRESS"] = "192.168.1.5"
    ENV["SMTP_PORT"] = "25"

    assert_not InstanceMail.smtp_settings.key?(:authentication)
    assert_not InstanceMail.smtp_settings.key?(:user_name)
  end

  test "SMTP_FROM wins, and the fallback sender uses the instance's own host" do
    ENV["SMTP_ADDRESS"] = "smtp.example.com"
    ENV["SMTP_USERNAME"] = "apikey"
    ENV["APP_HOST"] = "https://assistant.example.org"
    assert_equal "assistant@assistant.example.org", InstanceMail.from

    ENV["SMTP_FROM"] = "Our Assistant <home@example.org>"
    assert_equal "Our Assistant <home@example.org>", InstanceMail.from
  end

  test "the test environment keeps its test delivery whatever the ENV says" do
    ENV["SMTP_ADDRESS"] = "smtp.example.com"
    InstanceMail.apply!

    assert_equal :test, ActionMailer::Base.delivery_method
  end

  test "outside test, a configured instance switches ActionMailer to its SMTP" do
    ENV["SMTP_ADDRESS"] = "smtp.example.com"
    base = Class.new { class << self; attr_accessor :delivery_method, :smtp_settings; end }

    InstanceMail.apply!(base, env: ActiveSupport::EnvironmentInquirer.new("production"))

    assert_equal :smtp, base.delivery_method
    assert_equal "smtp.example.com", base.smtp_settings[:address]
  end

  test "the reset email comes from the instance's sender and links to the instance" do
    ENV["SMTP_ADDRESS"] = "smtp.example.com"
    ENV["SMTP_FROM"] = "home@example.org"

    mail = PasswordsMailer.reset(users(:one)).message
    assert_equal [ "home@example.org" ], mail.from
    assert_match %r{https?://example\.com/passwords/.+/edit}, mail.text_part.body.to_s
  end
end
