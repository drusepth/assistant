class CalendarController < ApplicationController
  # What the month can show, in the order a day cell stacks them: the
  # appointments, then what's due, then the pings you armed. Each one is a
  # toggle, remembered per browser so the month opens the way you left it.
  LAYERS = %w[ events tasks reminders ].freeze
  LAYERS_COOKIE = :calendar_layers

  # One armed moment of a reminder. A standing reminder stores only its next
  # delivery, so the month expands the rule to find the rest of them.
  ReminderOccurrence = Data.define(:reminder, :at)

  def show
    @month = month_from_params
    @layers = layers_from_params
    grid_range = @month.beginning_of_week..@month.end_of_month.end_of_week
    @weeks = grid_range.to_a.each_slice(7).to_a

    @events_by_day = @layers.include?("events") ? events_by_day(grid_range) : {}
    @tasks_by_day = @layers.include?("tasks") ? tasks_by_day(grid_range) : {}
    @reminders_by_day = @layers.include?("reminders") ? reminders_by_day(grid_range) : {}

    # Where you'll be (D-trip-spine): the stays on the viewer's trips — own
    # and joined — as a band under the day number, so the month answers the
    # nomad's question at a glance. Inclusive of the check-out day: you're
    # physically there that morning. A day claimed by two stays is a
    # double booking, and the band says so instead of quietly picking one.
    stays = Stay.joins(:trip).merge(Trip.involving(Current.user))
      .where(check_in: ..grid_range.last).where(check_out: grid_range.first..)
      .includes(:trip).order(:check_in, :id)

    @stays_by_day = stays.each_with_object({}) do |stay, by_day|
      span_start = [ stay.check_in, grid_range.first ].max
      span_end = [ stay.check_out, grid_range.last ].min
      (span_start..span_end).each { |day| (by_day[day] ||= []) << stay }
    end
  end

  private
    def events_by_day(grid_range)
      events = Event.visible_to(Current.user)
        .overlapping(grid_range.first.beginning_of_day..grid_range.last.end_of_day)
        .includes(:sections, :user)

      events.each_with_object({}) do |event, by_day|
        span_start = [ event.starts_at.to_date, grid_range.first ].max
        span_end = [ (event.ends_at || event.starts_at).to_date, grid_range.last ].min
        (span_start..span_end).each { |day| (by_day[day] ||= []) << event }
      end
    end

    # A task sits on its due date — the one day it has. Done ones stay, struck
    # through, so a past month still reads as what got done when.
    def tasks_by_day(grid_range)
      Task.visible_to(Current.user).where(due_on: grid_range)
        .includes(:sections, :user).order(:completed_at, :created_at)
        .group_by(&:due_on)
    end

    # Reminders are delivery, not content, so only the viewer's own. A
    # standing one shows every occurrence from the one it has armed onward;
    # the ones it already fired aren't stored, so a past month shows only
    # one-shots.
    def reminders_by_day(grid_range)
      zone = Current.user.household&.zone || Time.zone
      window = zone.local(grid_range.first.year, grid_range.first.month, grid_range.first.day)..
        zone.local(grid_range.last.year, grid_range.last.month, grid_range.last.day).end_of_day

      reminders = Current.user.reminders.where(deliver_at: ...window.end)
        .where("reminders.rule IS NOT NULL OR reminders.deliver_at >= ?", window.begin)
        .includes(:subject).order(:deliver_at)

      occurrences = reminders.flat_map do |reminder|
        if reminder.standing? && reminder.delivered_at.nil? && reminder.recurrence&.standing?
          reminder.recurrence.occurrences(reminder.local_deliver_at)
            .lazy.take_while { |at| at <= window.end }.select { |at| window.cover?(at) }
            .map { |at| ReminderOccurrence.new(reminder:, at:) }.to_a
        elsif window.cover?(reminder.deliver_at)
          [ ReminderOccurrence.new(reminder:, at: reminder.local_deliver_at) ]
        else
          []
        end
      end

      occurrences.sort_by(&:at).group_by { |occurrence| occurrence.at.in_time_zone(zone).to_date }
    end

    # `?layers=events,tasks` picks what shows and is remembered; a visit
    # without it reopens on the last choice, and everything shows at first.
    def layers_from_params
      if params.key?(:layers)
        layers = params[:layers].to_s.split(",") & LAYERS
        cookies.permanent[LAYERS_COOKIE] = { value: layers.join(","), same_site: :lax }
        layers
      elsif cookies.key?(LAYERS_COOKIE)
        cookies[LAYERS_COOKIE].to_s.split(",") & LAYERS
      else
        LAYERS
      end
    end

    def month_from_params
      Date.new(params.fetch(:year, Date.current.year).to_i, params.fetch(:month, Date.current.month).to_i, 1)
    rescue ArgumentError, RangeError
      raise ActionController::RoutingError, "invalid month"
    end
end
