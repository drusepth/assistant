require "test_helper"

# The app-wide CSP shipped with the vault (PASSWORDS_PLAN §4.8). XSS is the
# one attack class that turns "encrypted at rest" into no vault at all —
# script running as the user can call the reveal endpoint — so the policy is
# a regression test, not a config file nobody looks at again.
class SecurityHeadersTest < ActionDispatch::IntegrationTest
  setup do
    post session_url, params: { email_address: users(:one).email_address, password: "password" }
  end

  test "every page carries a script-src that blocks inline script" do
    get root_url
    policy = response.headers["Content-Security-Policy"]

    assert_match(/script-src [^;]*'self'/, policy)
    assert_no_match(/script-src [^;]*'unsafe-inline'/, policy)
    assert_no_match(/script-src [^;]*'unsafe-eval'/, policy)
    assert_match(/object-src 'none'/, policy)
    assert_match(/frame-ancestors 'self'/, policy)
    assert_match(/base-uri 'self'/, policy)
    assert_match(/form-action 'self'/, policy)
  end

  test "the importmap's inline tags carry the nonce the policy names" do
    get credentials_url
    nonce = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]

    assert_not_nil nonce, "script-src must name a nonce or the importmap won't run"
    assert_match(/<script type="importmap"[^>]*nonce="#{Regexp.escape(nonce)}"/, response.body)
    assert_match(/<script type="module" nonce="#{Regexp.escape(nonce)}">/, response.body)
  end

  test "no view ships an inline event handler for the policy to break" do
    inline_handlers = Dir[Rails.root.join("app/views/**/*.erb"), Rails.root.join("app/components/**/*.erb")]
      .select { |path| File.read(path).match?(/\son(click|change|submit|load|input|focus|blur)=/) }

    assert_empty inline_handlers, "use a Stimulus action — inline handlers are blocked by the CSP"
  end
end
