require "csv"

# Shared plumbing for CSV-based address book formats: header parsing for
# `handles?` sniffing, row iteration, and tolerant date parsing (exports
# disagree on birthday formats).
class People::Import::CsvBase
  def self.handles?(filename, content)
    return false if content.lstrip.start_with?("BEGIN:VCARD")
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

  def contacts
    rows.map { |row| build_contact(row) }
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

    def join_present(*parts)
      parts.compact.reject(&:blank?).join(" ").presence
    end
end
