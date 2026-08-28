require "test_helper"

# robots.txt is computed rather than shipped (D-about-pages), because a
# static file would advertise the /about tree to crawlers even on the
# installation that turned it off.
class RobotsControllerTest < ActionDispatch::IntegrationTest
  test "invites crawlers into /about and nowhere else while it is public" do
    get "/robots.txt"

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match(/^Allow: \/about$/, response.body)
    assert_match(/^Disallow: \/$/, response.body)
    assert_match(%r{^Sitemap: https?://\S+/about/sitemap$}, response.body)
  end

  test "disallows everything once public pages are off" do
    households(:smith).update!(public_pages_enabled: false)

    get "/robots.txt"

    assert_response :success
    assert_no_match(/about/, response.body)
    assert_match(/^Disallow: \/$/, response.body)
  end

  # The static file this replaced would have been served ahead of the route
  # by the public file server, silently winning forever.
  test "no static robots.txt shadows the route" do
    assert_not Rails.root.join("public/robots.txt").exist?
  end
end
