class GroupsController < ApplicationController
  def create
    lens = People::Group.find_or_create!(params[:name])
    redirect_to section_path("people"), notice: "#{lens.name} created — it has its own page now."
  rescue ArgumentError
    redirect_to section_path("people"), alert: "A group needs a name."
  end

  # Only custom lenses are removable — the seeded taxonomy is not. Tagged
  # items survive; they just lose this tag.
  def destroy
    lens = Section.custom.find(params[:id])
    lens.destroy!
    redirect_to section_path("people"), notice: "#{lens.name} removed. Your items kept their other tags."
  end
end
