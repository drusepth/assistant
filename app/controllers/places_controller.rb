# The places the user subscribes to (D-place-subscriptions): each one a
# gazetteer-named point with a radius and a lead time, and under it the
# calendars followed for it. Per user, never shared — `Current.user.places`
# is the whole authorization.
class PlacesController < ApplicationController
  before_action :set_place, only: %i[ update destroy ]

  def index
    @places = Current.user.places.includes(:listing_sources).to_a
    @place = Current.user.places.new
    @home = home_suggestion
    @next_up = next_up_by_place
    # Somebody looked: the sweep backs off sources nobody opens, and this is
    # the page that says somebody did.
    @places.each(&:touch_opened!)
  end

  def create
    @place = Current.user.places.new(place_params)
    if @place.save
      redirect_to places_path, notice: "Added #{@place.qualified_name}. Now follow a calendar or two for it."
    else
      redirect_to places_path, alert: @place.errors.full_messages.to_sentence
    end
  end

  def update
    if @place.update(place_params)
      redirect_to places_path, notice: "#{@place.name} updated."
    else
      redirect_to places_path, alert: @place.errors.full_messages.to_sentence
    end
  end

  def destroy
    @place.destroy!
    redirect_to places_path, notice: "Removed #{@place.name}. Anything you added to your calendar from it stays."
  end

  private
    def set_place
      @place = Current.user.places.find(params[:id])
    end

    def place_params
      params.expect(place: %i[ name radius_km lead_days alerts ])
    end

    # Home is offered, never assumed: the last line of the household address
    # is a human's free text for letters, and polling on a silent parse of it
    # is the wrong kind of helpful. Offered only while no place is here yet.
    def home_suggestion
      return nil if @places.any?

      line = Current.user.household.address_lines.last.to_s
      town = line.split(",").first.to_s.gsub(/\b\d{4,}\b/, "").squish
      town if town.present? && Datasets::Places.current.named(town)
    end

    def next_up_by_place
      @places.index_with { |place| Radar::River.new(Current.user, place: place).items(3) }
    end
end
