class CalendarController < ApplicationController
  def show
    @month = month_from_params
    grid_range = @month.beginning_of_week..@month.end_of_month.end_of_week
    @weeks = grid_range.to_a.each_slice(7).to_a

    events = Event.visible_to(Current.user)
      .overlapping(grid_range.first.beginning_of_day..grid_range.last.end_of_day)
      .includes(:sections)

    @events_by_day = events.each_with_object({}) do |event, by_day|
      span_start = [ event.starts_at.to_date, grid_range.first ].max
      span_end = [ (event.ends_at || event.starts_at).to_date, grid_range.last ].min
      (span_start..span_end).each { |day| (by_day[day] ||= []) << event }
    end

    # Where you'll be (D-trip-spine): the stays on the viewer's trips — own
    # and joined — as a band under the day number, so the month answers the
    # nomad's question at a glance. Inclusive of the check-out day: you're
    # physically there that morning. First stay wins a contested day; the
    # trip page has the detail.
    stays = Stay.joins(:trip).merge(Trip.involving(Current.user))
      .where(check_in: ..grid_range.last).where(check_out: grid_range.first..)
      .includes(:trip).order(:check_in, :id)

    @stay_by_day = stays.each_with_object({}) do |stay, by_day|
      span_start = [ stay.check_in, grid_range.first ].max
      span_end = [ stay.check_out, grid_range.last ].min
      (span_start..span_end).each { |day| by_day[day] ||= stay }
    end
  end

  private
    def month_from_params
      Date.new(params.fetch(:year, Date.current.year).to_i, params.fetch(:month, Date.current.month).to_i, 1)
    rescue ArgumentError, RangeError
      raise ActionController::RoutingError, "invalid month"
    end
end
