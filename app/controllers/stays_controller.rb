# A trip's lodging (D-trip-spine). Any traveller on the trip — owner or
# companion — can add and edit stays: the itinerary is the thing the
# household plans together.
class StaysController < ApplicationController
  include TripAccess

  before_action :set_trip, only: %i[ new create ]
  before_action :set_stay, only: %i[ edit update destroy ]

  def new
    @stay = @trip.stays.new(check_in: default_check_in, check_out: nil)
  end

  def create
    @stay = @trip.stays.new(stay_params)
    if @stay.save
      redirect_to trip_path(@trip, anchor: "itinerary"), notice: "Stay added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @stay.update(stay_params)
      redirect_to trip_path(@trip, anchor: "itinerary"), notice: "Stay updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @stay.destroy!
    redirect_to trip_path(@trip, anchor: "itinerary"), notice: "Stay removed."
  end

  private
    def set_trip
      @trip = find_trip_as_traveler(params[:trip_id])
    end

    def set_stay
      @stay = Stay.find(params[:id])
      @trip = find_trip_as_traveler(@stay.trip_id)
    end

    # A new stay usually starts where the last one ended — the nomad's
    # check-out day is the next check-in day.
    def default_check_in
      @trip.stays.by_date.last&.check_out || @trip.starts_on
    end

    def stay_params
      params.expect(stay: [ :location, :name, :kind, :booking_status, :check_in, :check_out,
                            :url, :confirmation_code, :notes ])
    end
end
