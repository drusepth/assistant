class HobbiesController < ApplicationController
  def create
    lens = Hobbies::Lens.find_or_create!(params[:name])
    # A new hobby is a question about every feed already followed, not just
    # the ones parked in the catch-all (D-hobby-feeds §4).
    Hobbies::MapFeeds.enqueue(Current.user, [ lens ])
    redirect_to section_path("hobbies"), notice: "#{lens.name} added to your hobbies."
  rescue ArgumentError
    redirect_to section_path("hobbies"), alert: "A hobby needs a name."
  end

  # Only custom lenses are removable — the seeded taxonomy is not, and
  # neither is the catch-all, which is `custom: false` for exactly this
  # reason. Tagged items survive; they just lose this tag.
  def destroy
    lens = Section.custom.find(params[:id])
    # `section_taggings` is `dependent: :destroy`, so a feed whose only lens
    # was this one is about to have none — and the invariant says every feed
    # has a hobby or has Other Interests. The rows have to be collected
    # before the cascade, because afterwards nothing remembers them.
    stranded = Feed.in_section(lens.id).to_a
    lens.destroy!
    Hobbies::OtherInterests.absorb!(stranded.each(&:reload))

    redirect_to section_path("hobbies"), notice: "#{lens.name} removed. Your items kept their other tags."
  end
end
