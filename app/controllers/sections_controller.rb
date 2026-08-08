class SectionsController < ApplicationController
  def show
    @section = Section.find_by!(slug: params[:slug])
    section_ids = [ @section.id, *@section.children.ids ]

    @tools = Tool.for_section(@section)
    @subsection_summaries = Sections::Summary.for(Current.user, @section.children)

    # Health leads with its care radar and coverage card (docs/HEALTH.md) —
    # the section-specific panel pattern the Hobbies capture card set. The
    # panels carry their tools with better context, so the Act zone drops
    # those cards to stay scannable.
    if @section.slug == "health"
      @tools = @tools.reject { |tool| Health::PANEL_TOOL_SLUGS.include?(tool.slug) }
      @care_statuses = Health::CareRadar.new(Current.user).statuses
      @family_care = family_care
      @coverage_documents = Health::Coverage.documents(Current.user)
      @medications = Current.user.notes.medications.order(:title)
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

  private
    # Other household members' care radars, over exactly the events they
    # share with the current user (visible_to is the only read path — a
    # member who shares nothing simply doesn't appear). Kids are users too;
    # this is how a parent sees the kid's dentist visit they'll be driving to.
    def family_care
      Current.user.household.users.where.not(id: Current.user.id).order(:name).filter_map do |member|
        tracked = Health::CareRadar.new(member, viewer: Current.user).statuses
          .select { |status| status.last_visit || status.next_visit }
        [ member, tracked ] if tracked.any?
      end
    end
end
