require "csv"

module Datasets
  # CPI-U annual averages — what "your pay lost 6% of its buying power"
  # is computed from. Reads the refreshed file when one exists, else the
  # shipped seed; absent data degrades to nil, never to a guess.
  class Cpi
    FILENAME = "cpi_u.csv".freeze

    def self.current = new

    def initialize(path: Datasets.read_path(FILENAME))
      @values = load_values(path)
    end

    def present? = @values.any?

    def latest_year = @values.keys.max

    def value_for(year) = @values[year]

    # Percent change in the index between the given date's year and the
    # latest year on file; nil when either end is missing — no data, no
    # claim.
    def drift_since(date)
      base = value_for(date.year)
      latest = value_for(latest_year)
      return nil unless base && latest && latest_year > date.year

      ((latest / base) - 1) * 100
    end

    private
      def load_values(path)
        return {} unless path

        CSV.read(path, headers: true).each_with_object({}) do |row, values|
          year = row["year"].to_i
          value = row["value"].to_f
          values[year] = value if year.positive? && value.positive?
        end
      rescue CSV::MalformedCSVError
        {}
      end
  end
end
