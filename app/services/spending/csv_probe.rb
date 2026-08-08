# Reads the first few rows of an unfamiliar bank CSV so the mapping form
# can offer headers, sample values, and a best guess at each column and
# the date format. Guesses are prefills, never decisions — the user
# confirms the mapping, and it's saved on the account for next time.
class Spending::CsvProbe
  SAMPLE_ROWS = 4
  DATE_FORMATS = [ "%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%m/%d/%y", "%d/%m/%y", "%d.%m.%Y", "%b %d, %Y", "%d %b %Y" ].freeze

  attr_reader :headers, :samples

  def initialize(content)
    table = CSV.parse(content.to_s, headers: true, liberal_parsing: true, skip_blanks: true)
    @headers = Array(table.headers).compact.map(&:to_s)
    @samples = table.first(SAMPLE_ROWS).map { |row| row.to_h { |header, value| [ header.to_s, value.to_s ] } }
  rescue CSV::MalformedCSVError
    @headers = []
    @samples = []
  end

  def parsed? = headers.any?

  def guess
    {
      "date" => header_matching(/\A(trans(action)?\s*)?date\z|date/i) || date_looking_header,
      "description" => header_matching(/desc|payee|name|merchant|memo|detail|narrative/i),
      "amount" => header_matching(/\Aamount\z|amount/i),
      "debit" => header_matching(/debit|withdrawal|money.?out|paid.?out/i),
      "credit" => header_matching(/credit|deposit|money.?in|paid.?in/i),
      "date_format" => guess_date_format,
      "sign" => "negative_out"
    }
  end

  private
    def header_matching(pattern)
      headers.find { |header| header.match?(pattern) }
    end

    def date_looking_header
      headers.find do |header|
        values = sample_values(header)
        values.any? && values.all? { |value| DATE_FORMATS.any? { |format| strict_parse(value, format) } }
      end
    end

    # First format that parses every sample date. Ambiguous m/d vs d/m
    # (all samples ≤ 12) falls to the US order in the list — the form's
    # date-format select is where the user corrects that.
    def guess_date_format
      column = header_matching(/date/i) || date_looking_header
      values = sample_values(column)
      return nil if values.empty?

      DATE_FORMATS.find { |format| values.all? { |value| strict_parse(value, format) } }
    end

    def sample_values(header)
      return [] if header.blank?
      samples.filter_map { |row| row[header].presence&.strip }
    end

    def strict_parse(value, format)
      Date.strptime(value, format)
    rescue Date::Error
      nil
    end
end
