class SectionsController < ApplicationController
  def show
    @section = Section.find_by!(slug: params[:slug])
    section_ids = [ @section.id, *@section.children.ids ]

    @tools = Tool.for_section(@section)

    # Health leads with its care radar and coverage card (docs/HEALTH.md) —
    # the section-specific panel pattern the Hobbies capture card set.
    if @section.slug == "health"
      @care_statuses = Health::CareRadar.new(Current.user).statuses
      @coverage_documents = Health::Coverage.documents(Current.user)
      @last_check_in = Current.user.tool_runs.where(tool_slug: "check_in", status: :done)
        .order(created_at: :desc).first
    end

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
