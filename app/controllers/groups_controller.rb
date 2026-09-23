class GroupsController < ApplicationController
  def create
    lens = People::Group.find_or_create!(params[:name])
    # Straight onto the new group's page, cursor in "Who's in it?": a group
    # is its people, and the next thing anyone does is add them
    # (D-person-picker). An empty group left on the grid stays empty.
    redirect_to section_path(lens.slug, fresh: 1), notice: "#{lens.name} created. Who's in it?"
  rescue ArgumentError
    redirect_to section_path("people"), alert: "A group needs a name."
  end

  # Only custom lenses are removable — the seeded taxonomy is not, and
  # neither is a lens a record owns (D-pet-primitive: Rex's lens is Rex's,
  # and removing the pet is what removes it). Tagged items survive; they
  # just lose this tag.
  def destroy
    lens = Section.custom.find(params[:id])
    if lens.lens_owner
      return redirect_to section_path(lens.slug),
        alert: "#{lens.name} belongs to a #{lens.lens_owner.downcase} — remove the #{lens.lens_owner.downcase} to remove this lens."
    end

    lens.destroy!
    redirect_to section_path("people"), notice: "#{lens.name} removed. Your items kept their other tags."
  end
end
