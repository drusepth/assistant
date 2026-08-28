require "application_system_test_case"
require Rails.root.join("db/demo")

# The screenshot pipeline (docs/ABOUT_PLAN.md §7).
#
# Not a test in the usual sense — it is the capture run, written as a system
# test so it gets a real browser and a real server for free, and so the
# images regenerate from the app rather than rotting in a folder somebody
# updated by hand in 2024. It lives under test/system/ precisely because
# `bin/rails test` skips that directory: capturing takes a minute and writes
# into the repository, which is not something a unit run should do.
#
# Drive it with `bin/rails screenshots:capture`.
#
# Every image is of the demo household (db/demo.rb) — a fictional family —
# signed in as one of its members. Nothing real is ever photographed.
class AboutScreenshotsTest < ApplicationSystemTestCase
  WIDTH = 1440

  setup do
    Rails.application.load_seed
    Demo.seed!
    About::Shot.directory.mkpath
  end

  teardown { Demo.reset! }

  test "capture every registered shot" do
    captured = []

    About::Shot::LIST.group_by(&:user).each do |email, shots|
      sign_in_as(email)
      shots.each { |shot| captured << capture(shot) }
    end

    # A capture run that quietly produced nothing is the failure mode this
    # whole file exists to prevent, so it fails rather than reports success.
    assert_equal About::Shot.names.sort, captured.sort
    puts "\nCaptured #{captured.size} screenshots into #{About::Shot.directory.relative_path_from(Rails.root)}"
  end

  private
    def sign_in_as(email)
      visit new_session_path
      fill_in "email_address", with: email
      fill_in "password", with: Demo::PASSWORD
      click_on "Sign in"
      assert_no_current_path new_session_path, wait: 5
    end

    # Scrollbars are an artefact of the capture, not of the app — they read
    # as chrome in a picture that is meant to be all product.
    HIDE_SCROLLBARS = <<~CSS.freeze
      ::-webkit-scrollbar { display: none !important; }
      * { scrollbar-width: none !important; }
    CSS

    def capture(shot)
      page.driver.browser.manage.window.resize_to(WIDTH, shot.height || 2200)
      visit shot.path
      # The page is done when the sidebar has drawn; without a settle the
      # lazy images and the map's own layout land halfway through the shot.
      assert_selector "body", wait: 5
      page.execute_script(<<~JS, HIDE_SCROLLBARS)
        const style = document.createElement("style");
        style.textContent = arguments[0];
        document.head.appendChild(style);
      JS
      sleep 0.4

      png = page.driver.browser.screenshot_as(:png)
      write_webp(png, shot)
      shot.name
    end

    # PNG in, WEBP out. Screenshots of flat UI compress about four to one
    # this way at a quality nobody can tell apart, and these files live in
    # the repository forever.
    def write_webp(png, shot)
      image = Vips::Image.new_from_buffer(png, "")
      image = image.resize(WIDTH.to_f / image.width) if image.width != WIDTH
      About::Shot.directory.join("#{shot.name}.webp")
        .binwrite(image.webpsave_buffer(Q: 82, strip: true))
    end
end
