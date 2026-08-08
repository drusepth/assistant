class SectionsController < ApplicationController
  def show
    @section = Section.find_by!(slug: params[:slug])
    section_ids = [ @section.id, *@section.children.ids ]

    @tools = Tool.for_section(@section)
    @suggestions = Current.user.suggestions.actionable.in_section(section_ids)
      .order(created_at: :desc).includes(:sections)

    # The People page is the social dashboard, not the roster (D30): the
    # circle is personal — own people, not visible_to — because the flag is
    # the owner's intent, and you don't tend your spouse's circle.
    if @section.slug == "people"
      @circle = Current.user.people.circle.stalest_first.includes(:sections)
      @upcoming_birthdays = Current.user.people.circle.birthday_within(30)
      @circle_candidates = Current.user.people.where(keep_in_touch: false).order(:name)
      @address_book_size = Person.visible_to(Current.user).count
    end

    @events = Event.visible_to(Current.user).in_section(section_ids).upcoming.includes(:sections, :user)
    @tasks = Task.visible_to(Current.user).in_section(section_ids).open.includes(:sections, :user)
    @documents = Document.visible_to(Current.user).in_section(section_ids).order(created_at: :desc).includes(:sections, :user)
    @people = Person.visible_to(Current.user).in_section(section_ids).order(:name).includes(:sections, :user)
    @goals = Goal.visible_to(Current.user).in_section(section_ids).where.not(status: :done).includes(:sections, :user)
    @notes = Note.visible_to(Current.user).in_section(section_ids).order(updated_at: :desc).includes(:sections, :user)
  end
end
