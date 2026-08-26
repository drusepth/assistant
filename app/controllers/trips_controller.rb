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
    @trip = Current.user.trips.new(starts_on: params[:starts_on].presence, ends_on: params[:ends_on].presence)
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
    @itinerary_map = Travel::ItineraryMap.new(@trip.stays.by_date) unless @trip.past?
    @comments = @trip.comments.chronological.includes(:user)
    @travelers = @trip.travelers
    # A planned trip whose dates have come and gone, with photos to show
    # for them, can earn its box (D-trip-spine) — the offer only when it
    # would actually work.
    @placeable = @own && !@trip.placed? && !@trip.upcoming? &&
      detector.covering(@trip.starts_on, @trip.ends_on).any?
  end

  # Gives a planned trip the box the detector would have given it: bounds,
  # cover and label all recomputed here from the owner's own photos, like
  # every number a trip ever stores.
  def place
    trip = find_trip_as_owner(params[:id])
    return redirect_to trip, alert: "This trip already has its map." if trip.placed?

    matches = detector.covering(trip.starts_on, trip.ends_on)
    return redirect_to trip, alert: "None of your photos from those dates carry a location yet." if matches.empty?

    best = matches.max_by(&:photo_count)
    trip.update!(**union_bounds(matches), cover_photo_id: best.cover_id,
      place_label: trip.place_label.presence || best.place_label)
    redirect_to trip, notice: "Trip placed — your photos from those dates are attached now."
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
      @detector ||= Travel::Trips.new(Photos::Map.new(Current.user.photos))
    end

    # One box around every overlapping candidate: a two-city trip the
    # detector saw as two runs still gets a single honest window.
    def union_bounds(candidates)
      bounds = candidates.map(&:bounds)
      { south: bounds.map { |b| b[:south] }.min, west: bounds.map { |b| b[:west] }.min,
        north: bounds.map { |b| b[:north] }.max, east: bounds.map { |b| b[:east] }.max }
    end
end
