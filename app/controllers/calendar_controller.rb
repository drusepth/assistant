# The calendar in three zooms — month, week, day — over one Calendar::Agenda.
# Each zoom is a URL, so back and bookmark work; the one you used last is
# remembered, so the sidebar's bare /calendar opens where you left off. So
# are the layers (events, tasks, reminders): a toggle is a `?layers=` link.
class CalendarController < ApplicationController
  VIEWS = %w[ month week day ].freeze
  VIEW_COOKIE = :calendar_view
  LAYERS_COOKIE = :calendar_layers

  def show
    remembered = cookies[VIEW_COOKIE]
    if params[:year].nil? && remembered.in?(%w[ week day ])
      return render_view(remembered, Date.current)
    end

    month = month_from_params
    render_view("month", month.all_month.cover?(Date.current) ? Date.current : month)
  end

  def week = render_view("week", date_from_params)

  def day = render_view("day", date_from_params)

  private
    def render_view(view, date)
      @view = view
      @date = date
      @layers = layers_from_params
      cookies.permanent[VIEW_COOKIE] = { value: view, same_site: :lax }

      @days = case view
      when "month" then date.beginning_of_month.beginning_of_week..date.end_of_month.end_of_week
      when "week" then date.beginning_of_week..date.end_of_week
      else date..date
      end
      @agenda = Calendar::Agenda.new(user: Current.user, days: @days, layers: @layers)
      @stays_by_day = stays_by_day(@days)

      render :show
    end

    # Where you'll be (D-trip-spine): the stays on the viewer's trips — own
    # and joined — as a band under the day number, so the month answers the
    # nomad's question at a glance. Inclusive of the check-out day: you're
    # physically there that morning. A day claimed by two stays is a
    # double booking, and the band says so instead of quietly picking one.
    def stays_by_day(days)
      stays = Stay.joins(:trip).merge(Trip.involving(Current.user))
        .where(check_in: ..days.last).where(check_out: days.first..)
        .includes(:trip).order(:check_in, :id)

      stays.each_with_object({}) do |stay, by_day|
        span_start = [ stay.check_in, days.first ].max
        span_end = [ stay.check_out, days.last ].min
        (span_start..span_end).each { |day| (by_day[day] ||= []) << stay }
      end
    end

    # `?layers=events,tasks` picks what shows and is remembered; a visit
    # without it reopens on the last choice, and everything shows at first.
    def layers_from_params
      layers = Calendar::Agenda::LAYERS
      if params.key?(:layers)
        chosen = params[:layers].to_s.split(",") & layers
        cookies.permanent[LAYERS_COOKIE] = { value: chosen.join(","), same_site: :lax }
        chosen
      elsif cookies.key?(LAYERS_COOKIE)
        cookies[LAYERS_COOKIE].to_s.split(",") & layers
      else
        layers
      end
    end

    def month_from_params
      Date.new(params.fetch(:year, Date.current.year).to_i, params.fetch(:month, Date.current.month).to_i, 1)
    rescue ArgumentError, RangeError
      raise ActionController::RoutingError, "invalid month"
    end

    def date_from_params
      Date.iso8601(params[:date])
    rescue ArgumentError, TypeError
      raise ActionController::RoutingError, "invalid date"
    end
end
