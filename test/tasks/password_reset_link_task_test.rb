require "test_helper"
require "rake"

# D-instance-mail: the operator's way back in when nobody can send mail.
class PasswordResetLinkTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("password:reset_link")
    Rake::Task["password:reset_link"].reenable
  end

  teardown { ENV.delete("EMAIL") }

  test "prints a working reset link for the account" do
    ENV["EMAIL"] = users(:one).email_address.upcase

    output, = capture_io { Rake::Task["password:reset_link"].invoke }

    url = output.lines.first.strip
    assert url.start_with?("https://example.com/passwords/"), url
    token = url.split("/")[-2]
    assert_equal users(:one), User.find_by_any_password_reset_token(token)
  end

  test "an unknown address stops with the accounts that do exist" do
    ENV["EMAIL"] = "nobody@example.com"

    error = assert_raises(SystemExit) do
      capture_io { Rake::Task["password:reset_link"].invoke }
    end
    assert_not error.success?
  end
end
