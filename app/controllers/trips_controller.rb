class TripsController < ApplicationController
  include TripAccess

  before_action :set_trip, only: :show
  before_action :set_own_trip, only: %i[ edit update destroy ]

  def index
    trips = Trip.involving(Current.user).includes(:stays, :legs).to_a
    @upcoming = trips.select(&:upcoming?).sort_by(&:starts_on)
    @underway = trips.select(&:underway?).sort_by(&:starts_on)
    @past = trips.select(&:past?).sort_by(&:starts_on).reverse
  end

  def new
    @trip = Current.user.trips.new(starts_on: params[:starts_on], ends_on: params[:ends_on])
  rescue Date::Error
    @trip = Current.user.trips.new
  end

  # Two births (D-trip-spine). Keeping a trip the detector spotted sends
  # `source: photos` plus only the date range being accepted — every number
  # stored is recomputed here from the user's own photos, so a hand-edited
  # form can move a trip's dates but can never invent a place it never
  # went. Planning a trip ahead sends the typed fields and stores no box.
  def create
    return create_from_candidate if params.dig(:trip, :source) == "photos"

    @trip = Current.user.trips.new(trip_params)
    if @trip.save
      redirect_to @trip, notice: "Trip created — start with where you'll stay."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @own = @trip.user_id == Current.user.id
    @map = @own && @trip.placed? ? Photos::Map.new(@trip.photos, bounds: @trip.map_bounds) : nil
    @photos = @own ? @trip.photos.with_attached_image.order(taken_at: :asc, id: :asc).limit(PHOTOS_SHOWN) : []
    @photo_count = @own ? @trip.photos.count : 0
    @posted = @trip.trip_photos.recent.includes(:user, photo: { image_attachment: :blob })
    @events = @trip.events(Current.user).includes(:sections, :user)
    @timeline = @trip.timeline
    @comments = @trip.comments.chronological.includes(:user)
    @travelers = @trip.travelers
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
      @trip = find_trip_as_traveler(params[:id])
    end

    def set_own_trip
      @trip = find_trip_as_owner(params[:id])
    end

    def trip_params
      params.expect(trip: [ :name, :place_label, :starts_on, :ends_on, :description ])
    end

    def create_from_candidate
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

    def detector
      Travel::Trips.new(Photos::Map.new(Current.user.photos))
    end
end
