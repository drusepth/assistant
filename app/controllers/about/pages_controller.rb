module About
  # The index, the top-level pages, the hubs, and the feature pages. Each
  # renders a partial named by a slug the registry already vouched for.
  class PagesController < BaseController
    def index
      @hubs = Page::HUBS
      @top_level = Page::TOP_LEVEL
      @tools = Tool.all
    end

    def show
      @page = registered!(Page.top_level(params[:slug]))
      @prose = prose_for("topics", @page.slug)
    end

    def hub
      @page = registered!(Page.hub(params[:slug]))
      @features = Page.features_for(@page.slug)
      @tools = @page.tools
      @featured = @page.featured_tools.presence || @tools
      @prose = prose_for("sections", @page.slug)
    end

    def feature
      @page = registered!(Page.feature(params[:slug]))
      @hub = Page.hub(@page.hub)
      @prose = prose_for("features", @page.slug)
    end
  end
end
