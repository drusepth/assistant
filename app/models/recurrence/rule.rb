# One recurrence grammar for the whole app (D-standing-reminders): the RFC
# 5545 RRULE subset real calendars produce — FREQ, INTERVAL, COUNT, UNTIL,
# WKST, BYDAY, BYMONTHDAY, BYMONTH — parsed once and expanded with
# calendar-aware arithmetic that keeps the wall-clock time across DST.
#
# Extracted from Events::Import::Ics, which still uses it to flatten a
# calendar's recurring events into one-off rows; a standing Reminder uses
# it to find the next moment to fire. A value object: no ActiveRecord, no
# clock of its own — every method takes the time it should reason from.
#
# Weekly rules expand within the *calendar* week (WKST, Monday by default),
# never the week relative to the start time. That is what the RFC says, and
# it is also what makes `next_after` a pure function of the current
# occurrence for INTERVAL > 1: any occurrence lies on the same fortnightly
# grid, so recomputing from it lands the same sequence.
module Recurrence
  class Rule
    FREQS = %w[ DAILY WEEKLY MONTHLY YEARLY ].freeze
    PARTS = %w[ FREQ INTERVAL COUNT UNTIL WKST BYDAY BYMONTHDAY BYMONTH ].freeze
    WEEKDAYS = { "SU" => 0, "MO" => 1, "TU" => 2, "WE" => 3, "TH" => 4, "FR" => 5, "SA" => 6 }.freeze
    WEEKDAY_CODES = WEEKDAYS.invert.freeze
    WORKDAYS = %w[ MO TU WE TH FR ].freeze
    DAY_NAMES = {
      "SU" => "Sunday", "MO" => "Monday", "TU" => "Tuesday", "WE" => "Wednesday",
      "TH" => "Thursday", "FR" => "Friday", "SA" => "Saturday"
    }.freeze
    UNITS = { "DAILY" => "day", "WEEKLY" => "week", "MONTHLY" => "month", "YEARLY" => "year" }.freeze

    # Candidate iterations before giving up — guards an ancient DTSTART
    # expanded toward today, or a rule that never lands (the 31st, monthly,
    # is fine; a malformed one might not be).
    MAX_STEPS = 20_000

    # A Rule for any non-blank text, so a caller can keep the raw rule of one
    # it can't expand (`supported?`); nil for nothing at all.
    def self.parse(text)
      return nil if text.blank?

      parts = text.split(";").each_with_object({}) do |pair, rule|
        key, val = pair.split("=", 2)
        rule[key.to_s.strip.upcase] = val.strip if val.present?
      end
      new(parts)
    end

    attr_reader :parts

    def initialize(parts)
      @parts = parts.freeze
    end

    def freq = parts["FREQ"]
    def interval = [ parts["INTERVAL"].to_i, 1 ].max
    def count = parts["COUNT"]&.to_i
    def weekdays = parts["BYDAY"].to_s.split(",").map(&:strip).select { |code| WEEKDAYS.key?(code) }
    def month_day = parts["BYMONTHDAY"]&.to_i

    # The rules real calendars produce. YEARLY BYMONTH/BYMONTHDAY are assumed
    # to restate the start (they always do in exports); anything cleverer is
    # left to the caller to keep as text.
    def supported?
      return false unless FREQS.include?(freq)
      return false if (parts.keys - PARTS).any?
      return false if parts["BYDAY"] && !%w[ WEEKLY MONTHLY ].include?(freq)
      return false if freq == "MONTHLY" && parts["BYDAY"] && !parts["BYDAY"].match?(/\A-?\d(SU|MO|TU|WE|TH|FR|SA)\z/)
      return false if freq == "WEEKLY" && parts["BYDAY"] && weekdays.empty?
      return false if parts["BYMONTHDAY"]&.include?(",")
      return false if parts["BYMONTH"] && freq != "YEARLY"
      true
    end

    # Whether the next occurrence is a pure function of the current one: what
    # a standing reminder needs, since it stores only the moment it fires
    # next. COUNT is the one part that isn't — it counts from a start the row
    # no longer remembers.
    def standing? = supported? && count.nil?

    # Occurrences in order, beginning at `start` (which is itself yielded when
    # it fits the rule), honoring COUNT and UNTIL. COUNT counts every
    # occurrence from the start even when a caller later discards some —
    # an EXDATEd instance still consumes its slot.
    def occurrences(start)
      Enumerator.new do |out|
        emitted = 0
        limit = until_limit(start)

        candidates(start).each do |time|
          emitted += 1
          break if (count && emitted > count) || (limit && time > limit)

          out << time
        end
      end
    end

    # The first occurrence strictly after `time`, walking forward from
    # `current` (an occurrence, or the moment a rule was first anchored to).
    # Nil when the rule has run out.
    def next_after(time, current:)
      occurrences(current).find { |candidate| candidate > time }
    end

    # Canonical text, in the RFC's own part order.
    def to_s
      PARTS.filter_map { |key| "#{key}=#{parts[key]}" if parts[key] }.join(";")
    end

    # "weekly on Thursday", "every 2 weeks on Monday, Friday", "monthly on
    # the 19th", "every weekday". Prose for a card or an import note.
    def describe
      unit = UNITS[freq]
      text = if interval > 1
        "every #{interval} #{unit.pluralize}"
      else
        { "day" => "daily", "week" => "weekly", "month" => "monthly", "year" => "yearly" }[unit]
      end

      if freq == "WEEKLY" && weekdays.sort == WORKDAYS.sort && interval == 1
        text = "every weekday"
      elsif freq == "WEEKLY" && weekdays.any?
        text += " on #{weekdays.map { |code| DAY_NAMES[code] }.join(', ')}"
      elsif freq == "MONTHLY" && (match = parts["BYDAY"].to_s.match(/\A(-?\d)(\w\w)\z/))
        ordinal = match[1].to_i
        text += " on the #{ordinal.negative? ? 'last' : ordinal.ordinalize} #{DAY_NAMES[match[2]]}"
      elsif freq == "MONTHLY" && month_day
        text += " on the #{month_day.ordinalize}"
      end
      text += ", #{count} times" if count
      if (limit = parts["UNTIL"] && parse_until(parts["UNTIL"], Time.zone))
        text += " until #{limit.strftime('%b %-d, %Y')}"
      end
      text
    end

    private
      def candidates(start)
        Enumerator.new do |out|
          case freq
          when "DAILY"
            0.upto(MAX_STEPS) { |n| out << start.advance(days: n * interval) }
          when "WEEKLY"
            weekly_candidates(start, out)
          when "MONTHLY"
            0.upto(MAX_STEPS) do |m|
              time = monthly_occurrence(start.advance(months: m * interval), start)
              out << time if time && time >= start
            end
          when "YEARLY"
            0.upto(MAX_STEPS) { |n| out << start.advance(years: n * interval) }
          end
        end
      end

      # The days of the calendar week holding `start`, then every INTERVAL-th
      # week after it. Arithmetic via `advance` so the wall-clock time holds
      # across a DST change inside the week.
      def weekly_candidates(start, out)
        wkst = WEEKDAYS.fetch(parts["WKST"].to_s.upcase, 1)
        offsets = (weekdays.presence&.map { |code| WEEKDAYS[code] } || [ start.wday ])
                    .map { |wday| (wday - wkst) % 7 }.sort
        week = start.advance(days: -((start.wday - wkst) % 7))

        0.upto(MAX_STEPS) do |w|
          base = week.advance(weeks: w * interval)
          offsets.each do |offset|
            time = base.advance(days: offset)
            out << time if time >= start
          end
        end
      end

      # BYMONTHDAY (or the start's day) skips months without that day, per
      # RFC; ordinal BYDAY ("2TU", "-1FR") resolves to the nth weekday.
      def monthly_occurrence(base, start)
        if (byday = parts["BYDAY"])
          match = byday.match(/\A(-?\d)(\w\w)\z/)
          match && nth_weekday(base, match[1].to_i, WEEKDAYS[match[2]])
        else
          day = month_day || start.day
          base.change(day: day) if Date.valid_date?(base.year, base.month, day)
        end
      end

      def nth_weekday(base, ordinal, wday)
        first = base.change(day: 1)
        last = base.end_of_month
        day = if ordinal.positive?
          1 + (wday - first.wday) % 7 + (ordinal - 1) * 7
        else
          last.day - (last.wday - wday) % 7 + (ordinal + 1) * 7
        end
        base.change(day: day) if day.positive? && day <= last.day
      end

      # UNTIL is a date (inclusive, so the end of that day where the series
      # lives) or a UTC date-time (RFC 5545 §3.3.10).
      def until_limit(start)
        return nil unless parts["UNTIL"]

        zone = start.respond_to?(:time_zone) ? start.time_zone : Time.zone
        parse_until(parts["UNTIL"], zone)
      end

      def parse_until(value, zone)
        value = value.to_s.strip
        if value.match?(/\A\d{8}\z/)
          date = Date.strptime(value, "%Y%m%d")
          zone.local(date.year, date.month, date.day).end_of_day
        elsif (m = value.match(/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?\z/i))
          numbers = m.captures[0, 6].map(&:to_i)
          m[7].present? ? Time.utc(*numbers).in_time_zone(zone) : zone.local(*numbers)
        end
      rescue ArgumentError, Date::Error
        nil
      end
  end
end
