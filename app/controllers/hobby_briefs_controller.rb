# What a hobby means, in the user's own words (D-story-matching §4), and
# whether the router is allowed to put stories in it at all.
#
# This is the whole surface: a sentence and a switch. Its predecessor was a
# list of words matched against headlines, which gave the user control at
# the price of being a rule nobody could keep correct. Prose costs nothing
# to be wrong about — it is context for a judgment, not the judgment.
class HobbyBriefsController < ApplicationController
  before_action :set_section
  before_action :set_brief

  def update
    @brief.assign_attributes(brief_params)
    return back(alert: @brief.errors.full_messages.to_sentence) unless @brief.save

    # A hobby switched back on is a question about the stories already here,
    # not only the ones still to come.
    resweep if @brief.saved_change_to_enabled? && @brief.enabled?

    back notice: "Saved."
  end

  # "Suggest a sentence" — one model call, asked for out loud.
  def author
    if Feeds::Briefs::Author.enqueue(Current.user, @section)
      back notice: "Reading your feeds for what #{@section.name} means…"
    else
      back alert: "No model is configured, so this one is yours to write."
    end
  end

  private
    def brief_params
      params.permit(:description, :enabled).with_defaults(enabled: @brief.enabled)
    end

    def set_section
      @section = Section.find_by(id: params[:section_id])
      back(alert: "That isn't a hobby.") unless routable?
    end

    # The catch-all has no brief: it is where a story lands when nothing
    # claims it, so routing *into* it would mean nothing.
    def routable?
      @section&.parent&.slug == "hobbies" && !Hobbies::OtherInterests.catch_all?(@section)
    end

    def set_brief = @brief = HobbyBrief.for(Current.user, @section)

    def resweep
      Feeds::RouteStories.resweep!(Current.user)
      Feeds::RouteStories.enqueue(Current.user)
      # The same sentence rides the event radar's prompt (D-event-radar).
      Radar::Match.resweep!(Current.user)
      Radar::Match.enqueue(Current.user)
    end

    def back(notice: nil, alert: nil)
      redirect_back fallback_location: @section ? section_path(@section.slug) : root_path,
        notice: notice, alert: alert
    end
end
