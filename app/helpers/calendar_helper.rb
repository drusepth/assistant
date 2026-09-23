module CalendarHelper
  CALENDAR_LAYER_LABELS = {
    "events" => [ "Events", :calendar ],
    "tasks" => [ "Tasks", :check_circle ],
    "reminders" => [ "Reminders", :bell ]
  }.freeze

  # The URL for one zoom of the calendar around `date`.
  def calendar_view_path(view, date, **options)
    case view
    when "month" then calendar_path(year: date.year, month: date.month, **options)
    when "week" then calendar_week_path(date: date.beginning_of_week.iso8601, **options)
    else calendar_day_path(date: date.iso8601, **options)
    end
  end

  # Back or forward one step of the current zoom.
  def calendar_step_path(view, date, direction)
    step = { "month" => 1.month, "week" => 1.week, "day" => 1.day }.fetch(view)
    calendar_view_path(view, direction == :next ? date + step : date - step)
  end

  def calendar_title(view, days, date)
    case view
    when "month" then date.strftime("%B %Y")
    when "week"
      first, last = days.first, days.last
      if first.month == last.month then "#{first.strftime("%b %-d")} – #{last.day}, #{last.year}"
      elsif first.year == last.year then "#{first.strftime("%b %-d")} – #{last.strftime("%b %-d")}, #{last.year}"
      else "#{first.strftime("%b %-d, %Y")} – #{last.strftime("%b %-d, %Y")}"
      end
    else date.strftime("%A, %B %-d")
    end
  end

  # "3p", "9:30a" — a clock time that fits in a month cell.
  def calendar_short_time(time)
    time.strftime(time.min.zero? ? "%-l%P" : "%-l:%M%P").delete_suffix("m")
  end

  # The data a draggable entry carries: what it is and the day it sits on.
  def calendar_drag_data(entry, day)
    return {} unless entry.movable_by?(Current.user)

    { kind: entry.kind, id: entry.record.id, day: day.iso8601,
      action: "dragstart->calendar-drag#start dragend->calendar-drag#end" }
  end

  # A day that can take a drop.
  def calendar_drop_data(day)
    { day: day.iso8601,
      action: "dragover->calendar-drag#over dragleave->calendar-drag#leave drop->calendar-drag#drop" }
  end
end
