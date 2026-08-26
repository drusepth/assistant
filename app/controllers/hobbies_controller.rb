class HobbiesController < ApplicationController
  def create
    lens = Hobbies::Lens.find_or_create!(params[:name])
    # If this name was one the spotter saw in the user's reading, the feeds
    # it stood on move under the new lens now — in this request, with no
    # model call, because the attribution was made when it was spotted
    # (D-hobby-spotting). Naming a hobby is what claims them; the spotter
    # never files anything itself.
    moved = Hobbies::Spotter.claim!(Current.user, lens)
    # And a new hobby is still a question about every feed already followed,
    # not just the ones parked in the catch-all (D-hobby-feeds §4).
    Hobbies::MapFeeds.enqueue(Current.user, [ lens ])
    # Feeds are only half of it: the stories about this hobby inside a feed
    # that is mostly about something else need words to find them
    # (D-story-matching). One call, in a job, and the editor works meanwhile.
    Feeds::Watchlists::Author.enqueue(Current.user, lens)
    redirect_to section_path("hobbies"), notice: created_notice(lens, moved)
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

  private
    def created_notice(lens, moved)
      return "#{lens.name} added to your hobbies." if moved.empty?

      "#{lens.name} added to your hobbies, with #{helpers.pluralize(moved.size, "feed")} moved over."
    end
end
