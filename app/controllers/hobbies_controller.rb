class HobbiesController < ApplicationController
  def create
    lens = Hobbies::Lens.find_or_create!(params[:name])
    redirect_to section_path("hobbies"), notice: "#{lens.name} added to your hobbies."
  rescue ArgumentError
    redirect_to section_path("hobbies"), alert: "A hobby needs a name."
  end

  # Only custom lenses are removable — the seeded taxonomy is not. Tagged
  # items survive; they just lose this tag.
  def destroy
    lens = Section.custom.find(params[:id])
    lens.destroy!
    redirect_to section_path("hobbies"), notice: "#{lens.name} removed. Your items kept their other tags."
  end
end
