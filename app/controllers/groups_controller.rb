class GroupsController < ApplicationController
  def create
    lens = People::Group.find_or_create!(params[:name])
    redirect_to section_path("people"), notice: "#{lens.name} created — it has its own page now."
  rescue ArgumentError
    redirect_to section_path("people"), alert: "A group needs a name."
  end

  # Only custom lenses are removable — the seeded taxonomy is not, and
  # neither is a lens a record owns (D-pet-primitive: Rex's lens is Rex's,
  # and removing the pet is what removes it). Tagged items survive; they
  # just lose this tag.
  def destroy
    lens = Section.custom.find(params[:id])
    if lens.owned?
      owner = lens.owner_type.underscore.humanize(capitalize: false)
      return redirect_to section_path(lens.slug),
        alert: "#{lens.name} belongs to a #{owner} — remove the #{owner} to remove this lens."
    end

    lens.destroy!
    redirect_to section_path("people"), notice: "#{lens.name} removed. Your items kept their other tags."
  end
end
