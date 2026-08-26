# A trip's transport (D-trip-spine): flights, drives, trains, car rentals.
# Same collaboration rule as stays — any traveller edits.
class TripLegsController < ApplicationController
  include TripAccess

  before_action :set_trip, only: %i[ new create ]
  before_action :set_leg, only: %i[ edit update destroy ]

  def new
    @leg = @trip.legs.new(kind: params[:kind].presence_in(TripLeg.kinds.keys) || "flight",
      starts_on: @trip.starts_on)
  end

  def create
    @leg = @trip.legs.new(leg_params)
    if @leg.save
      redirect_to trip_path(@trip, anchor: "itinerary"), notice: "#{@leg.kind_label} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @leg.update(leg_params)
      redirect_to trip_path(@trip, anchor: "itinerary"), notice: "#{@leg.kind_label} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @leg.destroy!
    redirect_to trip_path(@trip, anchor: "itinerary"), notice: "Removed from the itinerary."
  end

  private
    def set_trip
      @trip = find_trip_as_traveler(params[:trip_id])
    end

    def set_leg
      @leg = TripLeg.find(params[:id])
      @trip = find_trip_as_traveler(@leg.trip_id)
    end

    def leg_params
      params.expect(trip_leg: [ :kind, :booking_status, :starts_on, :ends_on, :departs_at,
                                :origin, :destination, :carrier, :confirmation_code, :cost, :url, :notes ])
    end
end
