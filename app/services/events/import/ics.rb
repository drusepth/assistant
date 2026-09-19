# iCalendar (.ics) parser covering the RFC 5545 exports produced by Google
# Calendar, Apple Calendar, Outlook, Proton, and most "subscribe" feeds:
# folded lines, escaped values, TZID/UTC/floating times, all-day date values
# (exclusive DTEND), DURATION, cancelled events, and recurrence — common
# RRULEs are expanded into concrete events within an import window, honoring
# EXDATE exclusions and edited instances (RECURRENCE-ID overrides).
class Events::Import::Ics
  # Recurring events become real rows only inside this window; the events
  # table has no recurrence model, so unbounded expansion is the alternative.
  WINDOW_BEHIND = 1.month
  WINDOW_AHEAD = 12.months
  MAX_OCCURRENCES = 500   # per rule, backstop on top of the window

  def self.handles?(filename, content)
    filename.to_s.match?(/\.(ics|ical|ifb)\z/i) || content.lstrip.start_with?("BEGIN:VCALENDAR")
  end

  def initialize(content)
    @content = content
  end

  def events
    vevents = parse_vevents
    overrides = override_keys_by_uid(vevents)
    vevents.flat_map { |props| build_events(props, overrides[value_of(props, "UID")]) }
  end

  private
    # Splits into VEVENT components, each an array of [name, params, value]
    # property triples with folding resolved. Nested components (VALARM) and
    # non-event components (VTIMEZONE) are skipped via the component stack.
    def parse_vevents
      result = []
      stack = []
      current = nil

      unfolded_lines.each do |line|
        name, params, value = parse_property(line)
        next unless name

        case name
        when "BEGIN"
          stack << value.upcase
          current = [] if value.casecmp?("VEVENT")
        when "END"
          if value.casecmp?("VEVENT") && current
            result << current
            current = nil
          end
          stack.pop
        else
          current << [ name, params, value ] if current && stack.last == "VEVENT"
        end
      end

      result
    end

    def unfolded_lines
      @content.split(/\r?\n/).each_with_object([]) do |line, lines|
        if line.start_with?(" ", "\t") && lines.any?
          lines[-1] += line[1..] # RFC folding: leading whitespace continues the line
        else
          lines << line
        end
      end
    end

    def parse_property(line)
      head, sep, value = line.partition(":")
      return nil if sep.empty?

      parts = head.split(";")
      name = parts.shift.to_s.upcase
      return nil if name.empty?

      params = parts.map { |p| p.split("=", 2) }
                    .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(k, v), h| h[k.to_s.upcase].concat(v.to_s.delete('"').split(",")) }

      [ name, params, value ]
    end

    # \, \; \n \\ escapes (RFC 5545).
    def unescape(value)
      value.to_s.gsub(/\\([\\,;nN])/) { |m| m[1].casecmp?("n") ? "\n" : m[1] }
    end

    def find(props, name)
      props.find { |n, _, _| n == name }
    end

    def value_of(props, name)
      find(props, name)&.last
    end

    # Edited instances of a recurring event arrive as separate VEVENTs with
    # the same UID plus a RECURRENCE-ID; the master's expansion must skip the
    # original slot so the override doesn't duplicate it.
    def override_keys_by_uid(vevents)
      vevents.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |props, overrides|
        recurrence_id = find(props, "RECURRENCE-ID")
        uid = value_of(props, "UID")
        next unless recurrence_id && uid

        value, = parse_time(recurrence_id[2], recurrence_id[1])
        overrides[uid] << occurrence_key(value) if value
      end
    end

    def build_events(props, override_keys)
      return [] if value_of(props, "STATUS").to_s.strip.casecmp?("CANCELLED")

      start_prop = find(props, "DTSTART")
      return [] unless start_prop
      start_value, all_day = parse_time(start_prop[2], start_prop[1])
      return [] unless start_value

      start_time = all_day ? start_value.in_time_zone : start_value
      rule = Recurrence::Rule.parse(value_of(props, "RRULE")) unless find(props, "RECURRENCE-ID")

      if rule&.supported?
        repeat_note = "Repeats: #{rule.describe}"
        exclusions = exclusion_keys(props) + override_keys.to_a
        starts = expand(start_time, rule).reject { |t| exclusions.include?(occurrence_key(all_day ? t.to_date : t)) }
      elsif rule
        # Exotic rule (BYSETPOS, HOURLY, …): keep the first occurrence and
        # the rule's own text so the pattern isn't silently lost.
        repeat_note = "Repeats: #{value_of(props, 'RRULE')}"
        starts = [ start_time ]
      else
        starts = [ start_time ]
      end

      title = unescape(value_of(props, "SUMMARY")).strip.presence
      location = unescape(value_of(props, "LOCATION")).strip.presence
      description = compose_description(props, repeat_note)
      span_days, duration = extent(props, start_value, start_time, all_day)
      uid = value_of(props, "UID").to_s.strip.presence
      url = value_of(props, "URL").to_s.strip.presence
      geo = parse_geo(value_of(props, "GEO"))
      # An expanded occurrence and an edited instance both share the master's
      # UID, so a consumer keying on UID needs to know it must add the start.
      recurring = rule.present? || find(props, "RECURRENCE-ID").present?
      status = value_of(props, "STATUS").to_s.strip.upcase.presence

      starts.map do |t|
        Events::Import::ParsedEvent.new(
          title: title,
          description: description,
          location: location,
          starts_at: t,
          ends_at: all_day ? (span_days && t.advance(days: span_days)) : (duration && t + duration),
          all_day: all_day,
          uid: uid, url: url, geo: geo, recurring: recurring, status: status
        )
      end
    end

    # GEO:lat;lng (RFC 5545 §3.8.1.6). Anything that isn't two numbers inside
    # the globe is no coordinate at all.
    def parse_geo(value)
      lat, lng = value.to_s.split(";", 2).map { |part| Float(part.to_s.strip, exception: false) }
      return nil unless lat && lng && lat.abs <= 90 && lng.abs <= 180

      [ lat, lng ]
    end

    # How long each occurrence lasts: whole days beyond the first for all-day
    # events (DTEND is exclusive, so a one-day event spans zero extra days →
    # ends_at nil, matching the app's convention), seconds otherwise.
    def extent(props, start_value, start_time, all_day)
      end_prop = find(props, "DTEND")
      end_value, = end_prop ? parse_time(end_prop[2], end_prop[1]) : nil

      if all_day
        last_day = end_value.is_a?(Date) ? end_value - 1 : nil
        span = last_day && last_day > start_value ? (last_day - start_value).to_i : nil
        [ span, nil ]
      else
        seconds = end_value ? end_value - start_time : parse_duration(value_of(props, "DURATION"))
        [ nil, seconds&.positive? ? seconds : nil ]
      end
    end

    def compose_description(props, repeat_note)
      lines = []
      description = value_of(props, "DESCRIPTION")
      lines << unescape(description).strip if description.present?

      if (organizer = find(props, "ORGANIZER"))
        name = Array(organizer[1]["CN"]).first.presence || organizer[2].to_s.sub(/\Amailto:/i, "")
        lines << "Organizer: #{unescape(name).strip}" if name.present?
      end
      url = value_of(props, "URL")
      lines << "Link: #{url.strip}" if url.present?
      lines << repeat_note if repeat_note

      lines.join("\n").presence
    end

    # --- times ---------------------------------------------------------------

    # Returns [value, all_day]: a Date for date-only values, otherwise a time
    # in the property's zone (TZID), UTC (trailing Z), or the app zone
    # (floating). Unknown TZIDs (e.g. Windows zone names) fall back to the
    # app zone rather than dropping the event.
    def parse_time(value, params = {})
      value = value.to_s.strip
      if value.match?(/\A\d{8}\z/)
        [ Date.strptime(value, "%Y%m%d"), true ]
      elsif (m = value.match(/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?\z/i))
        parts = m.captures[0, 6].map(&:to_i)
        time = m[7].present? ? Time.utc(*parts).in_time_zone : zone_for(params).local(*parts)
        [ time, false ]
      end
    rescue ArgumentError, Date::Error
      nil
    end

    def zone_for(params)
      tzid = Array(params["TZID"]).first
      (tzid && ActiveSupport::TimeZone[tzid]) || Time.zone
    end

    def parse_duration(value)
      m = value.to_s.match(/\AP(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?\z/)
      return nil unless m

      weeks, days, hours, minutes, seconds = m.captures.map(&:to_i)
      total = ((weeks * 7 + days) * 24 + hours) * 3600 + minutes * 60 + seconds
      total.positive? ? total : nil
    end

    def occurrence_key(value)
      value.is_a?(Date) ? value.iso8601 : value.to_i
    end

    def exclusion_keys(props)
      props.each_with_object(Set.new) do |(name, params, value), keys|
        next unless name == "EXDATE"
        value.split(",").each do |raw|
          excluded, = parse_time(raw, params)
          keys << occurrence_key(excluded) if excluded
        end
      end
    end

    # --- recurrence ----------------------------------------------------------

    # The grammar lives in Recurrence::Rule; this is only the import window.
    # A rule's COUNT is consumed by occurrences before the window too, and
    # EXDATEd instances still take their slot — exclusions are applied by the
    # caller, after counting.
    def expand(start_time, rule)
      window_start = WINDOW_BEHIND.ago
      window_end = WINDOW_AHEAD.from_now

      results = []
      rule.occurrences(start_time).each do |time|
        break if time > window_end || results.size >= MAX_OCCURRENCES
        results << time if time >= window_start
      end
      results
    end
end
