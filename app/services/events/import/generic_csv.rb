# Fallback for any other CSV with recognizable headers — a hand-kept
# spreadsheet, another app's export. Fuzzy-matches columns by name; the only
# requirements are something title-like and something date-like. Registered
# last so the branded formats claim their files first.
class Events::Import::GenericCsv < Events::Import::CsvBase
  TITLE = /\A(title|subject|event( name)?|summary)\z/i
  START_DATE = /\A(start ?date|date|start|when|day)\z/i

  def self.handles_headers?(headers)
    headers.any? { |h| h.match?(TITLE) } && headers.any? { |h| h.match?(START_DATE) }
  end

  private
    def build_event(row)
      start_date = parse_date(field(row, START_DATE))
      start_time = field(row, /\A(start ?time|time)\z/i)
      end_date = parse_date(field(row, /\Aend ?date\z/i))
      end_time = field(row, /\Aend ?time\z/i)

      starts_at = compose_time(start_date, start_time)
      ends_at = compose_time(end_date || start_date, end_time) if start_time.present? && end_time.present?
      ends_at = nil if ends_at && starts_at && ends_at <= starts_at

      Events::Import::ParsedEvent.new(
        title: field(row, TITLE),
        description: field(row, /\A(desc(ription)?|notes?|details)\z/i),
        location: field(row, /\A(location|place|where)\z/i),
        starts_at: starts_at,
        ends_at: ends_at,
        all_day: start_time.blank?
      )
    end

    def field(row, pattern)
      row.find { |key, _| key.match?(pattern) }&.last
    end
end
