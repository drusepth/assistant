module About
  # The tool directory and the ~60 pages under it.
  #
  # These are generated from the registry rather than written by hand: every
  # tool class already declares its title, description, sections, kind and
  # inputs, which is enough for a real page — what it is, what it asks you
  # for, and what it hands back. Prose for the flagship handful lives in an
  # optional per-tool partial, so writing one does not strand the other
  # fifty (docs/ABOUT_PLAN.md §3).
  class ToolsController < BaseController
    def index
      @tools = Tool.all.sort_by(&:title)
      @hubs = Page::HUBS.reject { |hub| hub.sections.empty? }
      # The contextual tools: registered on no section because they are
      # launched from the thing itself — a note, a task — rather than from
      # a section page. The directory is the one place they're browsable.
      @contextual = @tools.select { |tool| tool.section_slugs.empty? }
    end

    def show
      @tool = registered!(Tool.find(params[:slug]))
      @hubs = Page::HUBS.select { |hub| hub.sections.intersect?(@tool.section_slugs) }
      @prose = prose_for("tools", @tool.slug)
    end
  end
end
