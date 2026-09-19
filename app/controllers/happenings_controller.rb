# The river of what's on near your places (D-event-radar), and the verbs
# that make it more than a list: Add to calendar and Make a task are the
# one click that lands anything, Hide is for the thing you're simply not
# going to. Each verb re-renders just that row over Turbo.
class HappeningsController < ApplicationController
  before_action :set_happening, except: :index

  def index
    @places = Current.user.places.includes(:listing_sources).to_a
    @place = @places.find { |place| place.id.to_s == params[:place].to_s }
    @source = @place&.listing_sources&.find { |source| source.id.to_s == params[:source].to_s }
    # "Matched only" is on by default when a model is configured and absent
    # when it isn't — a filter that can never have anything in it is a
    # control that does nothing.
    @model = Current.user.household.model_profile&.configured?
    @matched_only = @model && params[:all].blank? && params[:show].blank?
    @river = Radar::River.new(Current.user, place: @place, source: @source, show: params[:show].to_s,
      matched: @matched_only, kind: params[:kind])
    @days = @river.days
    @place&.touch_opened!
  end

  def calendar
    event = @happening.add_to_calendar!
    act(notice: "Added “#{event.title}” to your calendar.")
  end

  def task
    task = @happening.make_task!
    act(notice: "Added “#{task.title}” to your board.")
  end

  def hide = act { @happening.hide! }
  def unhide = act { @happening.unhide! }

  # "Not this" (D-event-radar §5.4): the model said this was for you, and
  # it can be wrong. Rejecting tombstones the match — a re-read can't put
  # it back, the watcher retires its nudge, and the title becomes an
  # example the next batch is shown. Undo restores it.
  def reject = act { @happening.matches.find_by(target: params[:target])&.reject! }
  def unreject = act { @happening.happening_matches.rejected.find_by(target: params[:target])&.restore! }

  private
    # Rows are reachable only through the user's own places.
    def set_happening
      @happening = Happening.for_user(Current.user).find(params[:id])
    end

    def act(notice: nil)
      yield if block_given?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(helpers.dom_id(@happening),
            partial: "happenings/happening", locals: { happening: @happening, surface: params[:surface] })
        end
        format.html { redirect_back fallback_location: happenings_path, notice: notice }
      end
    end
end
