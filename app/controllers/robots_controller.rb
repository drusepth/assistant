# robots.txt, computed rather than shipped (D-about-pages).
#
# A static file would list the /about tree unconditionally, which is exactly
# backwards: the household that turned the public pages off is the one whose
# robots.txt would then be advertising the paths it hid. So the file is
# rendered — /about is crawlable only while it is actually public, and the
# rest of the app is disallowed either way.
class RobotsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_onboarding

  def show
    @public_pages = Household.public_pages?
    render plain: body, content_type: "text/plain"
  end

  private
    def body
      return "User-agent: *\nDisallow: /\n" unless @public_pages

      <<~TXT
        User-agent: *
        Allow: /about
        Disallow: /

        Sitemap: #{about_sitemap_url}
      TXT
    end
end
