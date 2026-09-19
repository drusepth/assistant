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
    @river = Radar::River.new(Current.user, place: @place, source: @source, show: params[:show].to_s)
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
