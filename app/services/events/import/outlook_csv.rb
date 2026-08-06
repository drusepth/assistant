# Desktop Outlook's calendar CSV export (File → Open & Export → Import/Export
# → Export to a file): one flat row per event with fixed columns. All-day
# events carry an exclusive End Date, midnight-to-midnight style.
class Events::Import::OutlookCsv < Events::Import::CsvBase
  def self.handles_headers?(headers)
    headers.include?("Subject") && headers.include?("Start Date")
  end

  private
    def build_event(row)
      all_day = row["All day event"].to_s.match?(/\A(true|yes)\z/i)
      start_date = parse_date(row["Start Date"])
      return Events::Import::ParsedEvent.new unless start_date

      end_date = parse_date(row["End Date"])
      if all_day
        starts_at = start_date.in_time_zone
        last_day = end_date && end_date - 1 # exclusive end
        ends_at = last_day && last_day > start_date ? last_day.in_time_zone : nil
      else
        starts_at = compose_time(start_date, row["Start Time"])
        ends_at = compose_time(end_date || start_date, row["End Time"]) if row["End Time"].present?
        ends_at = nil if ends_at && ends_at <= starts_at
      end

      Events::Import::ParsedEvent.new(
        title: row["Subject"],
        description: description(row),
        location: row["Location"],
        starts_at: starts_at,
        ends_at: ends_at,
        all_day: all_day
      )
    end

    # Columns without an Event home are kept as readable lines.
    def description(row)
      join_lines(
        row["Description"],
        ("Organizer: #{row['Meeting Organizer']}" if row["Meeting Organizer"].present?),
        ("Attendees: #{row['Required Attendees']}" if row["Required Attendees"].present?),
        ("Categories: #{row['Categories']}" if row["Categories"].present?)
      )
    end
end
