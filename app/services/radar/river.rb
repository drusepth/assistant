module Radar
  # What's on near the user's places (D-event-radar): the query behind
  # `/happenings`, the hub's Near-you card and the hobby pages' nearby list.
  # One authorization line — `Happening.for_user` — and every surface reads
  # through it, so no grant can widen what a river shows.
  #
  # Upcoming, in range, not hidden, not withdrawn, by date. The filters
  # narrow that; `show` swaps the pile (the hidden rows, or the ones a
  # place's radius put out of range) so a wrong radius or a hasty Hide is
  # diagnosable rather than silent.
  class River
    SHOWS = %w[ upcoming hidden out_of_range ].freeze
    PREVIEW = 5

    def initialize(user, place: nil, source: nil, show: "upcoming", horizon: Happening::HORIZON)
      @user = user
      @place = place
      @source = source
      @show = SHOWS.include?(show) ? show : "upcoming"
      @horizon = horizon
    end

    attr_reader :show

    def items(limit = nil)
      scope = limit ? base.limit(limit) : base
      scope.to_a
    end

    # Rows under their day — an opening has no date and sits under the day
    # it was first seen.
    def days(limit = nil) = items(limit).group_by(&:on)

    def count = base.count

    def any? = base.exists?

    private
      def base
        scope = Happening.for_user(@user).live.upcoming
          .where("happenings.starts_at IS NULL OR happenings.starts_at <= ?", @horizon.from_now)
          .includes(listing_source: :place).by_start
        scope = case @show
        when "hidden" then scope.hidden
        when "out_of_range" then scope.visible.where(out_of_range: true)
        else scope.visible.in_range
        end
        scope = scope.where(listing_source_id: @place.listing_sources.select(:id)) if @place
        scope = scope.where(listing_source: @source) if @source
        scope
      end
  end
end
