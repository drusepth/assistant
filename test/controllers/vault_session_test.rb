require "test_helper"

# The cookie-path registry (D-vault-sealed). The invariant under test is the
# one the path scoping exists for: the unwrapped vault key reaches the vault
# surfaces and nothing else — so a second surface means a second cookie, not
# a wider one.
class VaultSessionTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
  end

  def keyring_cookies
    Array(response.headers["set-cookie"]).select { |line| line.start_with?("keyring") }
  end

  test "sign-in sets one keyring cookie per vault surface, each path-scoped" do
    # Rails' jar is keyed by name alone, so the same name twice would leave
    # exactly one cookie and one silently unlocked surface.
    assert_equal VaultSession::COOKIES.size, VaultSession::COOKIES.values.uniq.size,
      "each vault surface needs its own cookie name"

    VaultSession::COOKIES.each do |path, name|
      line = keyring_cookies.find { |cookie| cookie.start_with?("#{name}=") }
      assert line, "no #{name} cookie was set at sign-in"
      assert_match(/path=#{Regexp.escape(path)}/i, line, "#{name} must be scoped to #{path}")
      assert_match(/httponly/i, line)
    end
  end

  test "no vault cookie is scoped to the whole app" do
    assert_equal VaultSession::COOKIES.size, keyring_cookies.size
    keyring_cookies.each do |line|
      assert_no_match(%r{path=/;}i, line, "a vault key scoped to / would ride every request in the app")
    end
  end

  test "locking clears every surface, not just the one locked from" do
    post lock_credentials_url

    VaultSession::COOKIES.each_value do |name|
      line = keyring_cookies.find { |cookie| cookie.start_with?("#{name}=") }
      assert line, "#{name} must be explicitly expired by a lock"
      assert_match(/#{name}=;/, line, "#{name} was not cleared")
    end
  end
end
