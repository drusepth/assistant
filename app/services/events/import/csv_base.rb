require "csv"

# Shared plumbing for CSV-based calendar formats: header parsing for
# `handles?` sniffing, row iteration, and tolerant date/time parsing
# (exports disagree on formats). A blank start time makes the event all-day,
# matching the app's convention.
class Events::Import::CsvBase
  def self.handles?(filename, content)
    return false if content.lstrip.start_with?("BEGIN:VCALENDAR", "BEGIN:VCARD")
    headers = parse_headers(content)
    headers.present? && handles_headers?(headers)
  rescue CSV::MalformedCSVError
    false
  end

  def self.parse_headers(content)
    first_line = content.lines.first.to_s
    CSV.parse_line(first_line.chomp, col_sep: sniff_separator(first_line))&.map { |h| h.to_s.strip }
  end

  # Outlook in some locales exports semicolon-separated CSV.
  def self.sniff_separator(header_line)
    header_line.count(";") > header_line.count(",") ? ";" : ","
  end

  def initialize(content)
    @content = content
  end

  def events
    rows.map { |row| build_event(row) }
  end

  private
    def rows
      CSV.parse(@content, headers: true, col_sep: self.class.sniff_separator(@content.lines.first.to_s),
                          liberal_parsing: true, skip_blanks: true)
         .map { |row| row.to_h.transform_keys { |k| k.to_s.strip }.transform_values { |v| v.to_s.strip.presence } }
    end

    def parse_date(value)
      return nil if value.blank?
      Date.iso8601(value)
    rescue Date::Error
      begin
        Date.strptime(value, "%m/%d/%Y")
      rescue Date::Error
        nil
      end
    end

    # "2:00:00 PM", "14:30" — anything Time.zone.parse understands, anchored
    # to the given day; unparseable times degrade to midnight, not a drop.
    def compose_time(date, time_string)
      return nil unless date
      return date.in_time_zone if time_string.blank?
      Time.zone.parse("#{date.iso8601} #{time_string}") || date.in_time_zone
    rescue ArgumentError
      date.in_time_zone
    end

    def join_lines(*parts)
      parts.compact.reject(&:blank?).join("\n").presence
    end
end
