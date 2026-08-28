require "test_helper"

# `webmock/minitest` blocks every outbound connection so no test can reach a
# model provider by accident. A system test's own plumbing is outbound
# connections — the runner talks to chromedriver, and the browser talks to
# the test server — both over localhost, so localhost is allowed back and
# nothing else is.
WebMock.disable_net_connect!(allow_localhost: true)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Selenium's default is to find Chrome on PATH and, failing that, to
  # download one. Neither works on a box with no `chrome` binary and no
  # outbound access — which is most containers, and the one the screenshot
  # capture runs in. Both are therefore overridable:
  #
  #   CHROME_BINARY=/path/to/chrome  CHROMEDRIVER=/path/to/chromedriver
  #
  # and, with neither set, the usual names are tried before falling back to
  # Selenium's own behaviour, so a laptop with Chrome installed needs no
  # configuration at all.
  BROWSERS = %w[ chromium chromium-browser google-chrome google-chrome-stable chrome ].freeze

  def self.chrome_binary
    ENV["CHROME_BINARY"].presence || BROWSERS.lazy.filter_map { |name| which(name) }.first
  end

  def self.which(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
      .map { |dir| File.join(dir, name) }
      .find { |path| File.executable?(path) && !File.directory?(path) }
  end

  if (driver = ENV["CHROMEDRIVER"].presence || which("chromedriver"))
    Selenium::WebDriver::Chrome::Service.driver_path = driver
  end

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    binary = chrome_binary
    options.binary = binary if binary
    # A container has no user namespace to sandbox into and a /dev/shm too
    # small for Chrome's default; both are the standard incantation.
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
  end
end
