module Radar
  # A trip's stay as a dated place (D-place-subscriptions): for each
  # upcoming located stay on a trip the user is on, the user's places whose
  # radius covers the stay's point, with the stay's nights as the window.
  # No row of its own — "what's on in Lisbon while we're there" is the
  # Lisbon place the user already follows calendars for, read between
  # check-in and check-out instead of inside the place's lead time.
  #
  # Nothing coordinate-derived crosses users here (Q14): a stay's point is
  # ordinary shared trip data, matched in memory against the viewer's own
  # places, and the rows that come back are the viewer's own.
  class Windows
    Window = Data.define(:trip, :stay, :place, :range) do
      def cover?(happening)
        happening.starts_at.present? && range.cover?(happening.starts_at.to_date) &&
          happening.listing_source.place_id == place.id
      end
    end

    def initialize(user, today: Date.current)
      @user = user
      @today = today
    end

    def all
      @all ||= stays.flat_map do |stay|
        places.select { |place| place.within?(stay.latitude, stay.longitude) }.map do |place|
          Window.new(trip: stay.trip, stay: stay, place: place, range: stay.check_in..stay.check_out)
        end
      end
    end

    def for_trip(trip) = all.select { |window| window.trip == trip }

    # Located stays on this trip with no place of the user's nearby — the
    # ones the trip page offers to add.
    def unplaced_for(trip)
      covered = for_trip(trip).map(&:stay).to_set
      trip.stays.by_date.select(&:located?).reject { |stay| covered.include?(stay) }
    end

    # Is this row inside one of the user's trip windows? What decides
    # whether the event it becomes is also filed under Travel.
    def cover?(happening) = all.any? { |window| window.cover?(happening) }

    private
      def stays
        @stays ||= Stay.joins(:trip).merge(Trip.involving(@user)).includes(:trip)
          .where(check_out: @today..).where.not(latitude: nil).by_date.to_a
      end

      def places = @places ||= @user.places.to_a
  end
end
