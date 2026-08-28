module About
  # The sitemap, generated from the same registry that serves the pages, so
  # it cannot list a page that doesn't exist or miss one that does.
  #
  # It sits behind the household switch like everything else in the tree —
  # an installation with the public pages off has no sitemap either, rather
  # than one enumerating the paths it just hid.
  class SitemapController < BaseController
    def show
      @paths = [ about_root_path, about_tools_path ] +
        Page::TOP_LEVEL.map { |page| about_page_path(page) } +
        Page::HUBS.map { |hub| about_hub_path(hub) } +
        Page::FEATURES.map { |feature| about_feature_path(feature) } +
        Tool::SLUGS.map { |slug| about_tool_path(slug) }

      render xml: sitemap
    end

    private
      def sitemap
        urls = @paths.map { |path| "  <url><loc>#{ERB::Util.html_escape(request.base_url + path)}</loc></url>" }

        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          #{urls.join("\n")}
          </urlset>
        XML
      end
  end
end
