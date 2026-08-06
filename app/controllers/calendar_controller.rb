class CalendarController < ApplicationController
  def show
    @month = month_from_params
    grid_range = @month.beginning_of_week..@month.end_of_month.end_of_week
    @weeks = grid_range.to_a.each_slice(7).to_a

    @events_by_day = Event.visible_to(Current.user)
      .between(grid_range.first.beginning_of_day..grid_range.last.end_of_day)
      .includes(:sections)
      .group_by { |event| event.starts_at.to_date }
  end

  private
    def month_from_params
      Date.new(params.fetch(:year, Date.current.year).to_i, params.fetch(:month, Date.current.month).to_i, 1)
    rescue ArgumentError, RangeError
      raise ActionController::RoutingError, "invalid month"
    end
end
