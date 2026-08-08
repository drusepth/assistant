class SectionsController < ApplicationController
  def show
    @section = Section.find_by!(slug: params[:slug])
    section_ids = [ @section.id, *@section.children.ids ]

    # A built-out section's lead panel (D37) carries its own data and hides
    # the tool cards it surfaces with better context; this controller never
    # changes per section.
    @panel = Sections::Panel.for(@section, Current.user)
    @tools = Tool.for_section(@section)
      .reject { |tool| @panel&.hidden_tool_slugs&.include?(tool.slug) }
    @subsection_summaries = Sections::Summary.for(Current.user, @section.children)

    @suggestions = Current.user.suggestions.actionable.in_section(section_ids)
      .order(created_at: :desc).includes(:sections)

    @events = Event.visible_to(Current.user).in_section(section_ids).upcoming.includes(:sections, :user)
    @tasks = Task.visible_to(Current.user).in_section(section_ids).open.includes(:sections, :user)
    @documents = Document.visible_to(Current.user).in_section(section_ids).order(created_at: :desc).includes(:sections, :user)
    @people = Person.visible_to(Current.user).in_section(section_ids).order(:name).includes(:sections, :user)
    @goals = Goal.visible_to(Current.user).in_section(section_ids).where.not(status: :done).includes(:sections, :user)
    @notes = Note.visible_to(Current.user).in_section(section_ids).order(updated_at: :desc).includes(:sections, :user)
  end
end
