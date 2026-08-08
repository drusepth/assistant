require "net/http"

module Datasets
  # Fetches the public datasets from BLS when the instance's network allows
  # (D31) — CPI-U annual averages via the public timeseries API (no key),
  # the OES/OEWS national wage table via its published zip. Fetched data
  # lands in storage/datasets/ and wins over the seeds; air-gapped installs
  # use the admin import instead and never need this to run. Each dataset
  # refreshes independently — one source down doesn't spoil the other.
  class Refresh
    CPI_API = URI("https://api.bls.gov/publicAPI/v2/timeseries/data/").freeze
    CPI_SERIES = "CUUR0000SA0".freeze
    CPI_YEARS_BACK = 9 # the unregistered API caps a request at 10 years
    OES_URL = "https://www.bls.gov/oes/special-requests/oesm%02dnat.zip".freeze
    MAX_DOWNLOAD_BYTES = 120.megabytes
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 120

    Result = Struct.new(:cpi_years, :wage_rows, :errors, keyword_init: true)

    def call
      errors = {}
      cpi_years = begin
        refresh_cpi!
      rescue StandardError => e
        errors[:cpi] = e.message
        nil
      end
      wage_rows = begin
        refresh_wages!
      rescue StandardError => e
        errors[:wages] = e.message
        nil
      end
      Result.new(cpi_years: cpi_years, wage_rows: wage_rows, errors: errors)
    end

    # Merges fetched annual averages over whatever is already on file, so a
    # 10-year API window never shrinks the series the seed started.
    def refresh_cpi!
      merged = Cpi.current.then { |cpi| (2015..Date.current.year).filter_map { |y| v = cpi.value_for(y); [ y, v ] if v }.to_h }
      merged.merge!(fetched_cpi_values)
      raise "BLS returned no annual averages" if merged.empty?

      csv = [ "year,value", *merged.sort.map { |year, value| "#{year},#{value}" } ].join("\n")
      Datasets.write!(Cpi::FILENAME, csv + "\n")
      Datasets.write!("cpi_u.yml", {
        "series_id" => CPI_SERIES, "source" => "api.bls.gov",
        "refreshed_at" => Time.current.iso8601
      }.to_yaml)
      merged.keys.max
    end

    def refresh_wages!
      year, archive = download_latest_oes
      rows, vintage = OewsWorkbook.parse(archive.path)
      detailed = rows.select { |row| row.group == "detailed" }
      raise "The OES workbook had no detailed occupation rows" if detailed.empty?

      write_wages!(detailed, vintage || "May #{year}", source: "bls.gov/oes")
      detailed.size
    ensure
      archive&.close!
    end

    # Shared with the admin import path: rows from any OewsWorkbook parse
    # land in the same storage files.
    def write_wages!(rows, as_of, source:)
      csv = +"occ_code,occ_title,h_median,a_median\n"
      rows.each do |row|
        csv << CSV.generate_line([ row.code, row.title, row.hourly_median, row.annual_median ])
      end
      Datasets.write!(Wages::FILENAME, csv)
      Datasets.write!(Wages::META_FILENAME, {
        "as_of" => as_of, "source" => source, "refreshed_at" => Time.current.iso8601
      }.to_yaml)
    end

    private
      def fetched_cpi_values
        body = {
          seriesid: [ CPI_SERIES ],
          startyear: (Date.current.year - CPI_YEARS_BACK).to_s,
          endyear: Date.current.year.to_s,
          annualaverage: true
        }.to_json
        response = post_json(CPI_API, body)
        raise "BLS API: #{response["message"].presence || response["status"]}" unless response["status"] == "REQUEST_SUCCEEDED"

        entries = response.dig("Results", "series", 0, "data") || []
        entries.select { |entry| entry["period"] == "M13" }
          .to_h { |entry| [ entry["year"].to_i, entry["value"].to_f ] }
      end

      def post_json(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        request.body = body
        response = http.request(request)
        raise "BLS API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      # BLS publishes the national file yearly; try the most recent vintages.
      def download_latest_oes
        failures = []
        [ Date.current.year, Date.current.year - 1, Date.current.year - 2 ].each do |year|
          uri = URI(format(OES_URL, year % 100))
          begin
            return [ year, download(uri) ]
          rescue StandardError => e
            failures << "#{uri}: #{e.message}"
          end
        end
        raise "No OES national file reachable (#{failures.join("; ")})"
      end

      def download(uri)
        tempfile = Tempfile.new([ "oes", ".zip" ])
        tempfile.binmode
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.request(Net::HTTP::Get.new(uri)) do |response|
          raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          bytes = 0
          response.read_body do |chunk|
            bytes += chunk.bytesize
            raise "download exceeded #{MAX_DOWNLOAD_BYTES / 1.megabyte}MB" if bytes > MAX_DOWNLOAD_BYTES

            tempfile.write(chunk)
          end
        end
        tempfile.flush
        tempfile
      rescue StandardError
        tempfile&.close!
        raise
      end
  end
end
