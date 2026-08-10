module NavigationHelper
  def nav_link_to(name, path, icon_name)
    active = nav_active?(path)
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    link_to path, class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}" do
      icon(icon_name, css_class: "size-4.5 shrink-0") + name
    end
  end

  def section_nav_link(section)
    active = request.path == section_path(section.slug)
    classes = active ?
      "bg-primary-600 text-primary-50 font-semibold" :
      "text-ink hover:bg-canvas"

    link_to section_path(section.slug), class: "flex items-center gap-2.5 rounded-full px-3 py-2 text-sm #{classes}" do
      tag.span("", class: "size-2 shrink-0 rounded-full #{section_dot_classes(section)}") + section.name
    end
  end

  private
    def nav_active?(path)
      return request.path == path if path == root_path
      request.path == path || request.path.start_with?("#{path}/")
    end
end
