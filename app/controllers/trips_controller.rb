class TripsController < ApplicationController
  before_action :set_trip, only: %i[ show edit update destroy ]

  # Saving a spotted trip. The client sends only the date range it is
  # accepting; every number stored is recomputed here from the user's own
  # photos, so a hand-edited form can move a trip's dates but can never
  # invent a place it never went.
  def create
    starts_on = Date.parse(params.expect(trip: [ :starts_on ])[:starts_on])
    candidate = detector.candidates.find { |proposal| proposal.starts_on == starts_on }
    return redirect_to section_path("travel"), alert: "That trip isn't in your photos any more." unless candidate

    trip = Current.user.trips.from_candidate(candidate, name: params.dig(:trip, :name))
    if trip.save
      redirect_to trip, notice: "Trip saved — rename it any time."
    else
      redirect_to section_path("travel"), alert: trip.errors.full_messages.to_sentence
    end
  rescue Date::Error, ActionController::ParameterMissing
    redirect_to section_path("travel"), alert: "That trip couldn't be saved."
  end

  def show
    @map = Photos::Map.new(@trip.photos, bounds: @trip.map_bounds)
    @photos = @trip.photos.with_attached_image.order(taken_at: :asc, id: :asc).limit(PHOTOS_SHOWN)
    @photo_count = @trip.photos.count
    @events = @trip.events(Current.user).includes(:sections, :user)
  end

  def edit
  end

  def update
    if @trip.update(trip_params)
      redirect_to @trip, notice: "Trip updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @trip.destroy!
    redirect_to section_path("travel"), notice: "Trip removed — your photos are untouched."
  end

  PHOTOS_SHOWN = 60

  private
    def set_trip
      @trip = Current.user.trips.find(params[:id])
    end

    def trip_params
      params.expect(trip: [ :name, :starts_on, :ends_on ])
    end

    def detector
      Travel::Trips.new(Photos::Map.new(Current.user.photos))
    end
end
