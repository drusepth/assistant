require "net/http"

module Datasets
  # Fetches the public datasets from BLS when the instance's network allows
  # (D-public-datasets) — CPI-U annual averages via the public timeseries API (no key),
  # the OES/OEWS national wage table via its published zip. Fetched data
  # lands in storage/datasets/ and wins over the seeds; air-gapped installs
  # use the admin import instead and never need this to run. Each dataset
  # refreshes independently — one source down doesn't spoil the other.
  class Refresh
    CPI_API = URI("https://api.bls.gov/publicAPI/v2/timeseries/data/").freeze
    CPI_SERIES = "CUUR0000SA0".freeze
    CPI_YEARS_BACK = 9 # the unregistered API caps a request at 10 years

    # bls.gov answers 403 to clients it doesn't recognize — a default
    # `User-Agent: Ruby` is refused at the edge before the file is ever
    # looked up, which is why every vintage failed identically. Identify the
    # instance instead, the way BLS asks automated callers to.
    USER_AGENT = "Mozilla/5.0 (compatible; assistant/1.0; +https://github.com/drusepth/assistant)".freeze

    # BLS has published the national zip under both spellings of the
    # directory and moves between them without notice; the file is small
    # enough to just try both rather than pin a guess.
    OES_URLS = [
      "https://www.bls.gov/oes/special.requests/oesm%02dnat.zip",
      "https://www.bls.gov/oes/special-requests/oesm%02dnat.zip"
    ].freeze
    OES_VINTAGES = 3
    MAX_DOWNLOAD_BYTES = 120.megabytes
    MAX_REDIRECTS = 3
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 120

    # `errors` holds the exceptions themselves, not their messages: the
    # /admin log wants the class and backtrace too.
    Result = Struct.new(:cpi_years, :wage_rows, :errors, keyword_init: true)

    def call
      errors = {}
      cpi_years = begin
        refresh_cpi!
      rescue StandardError => e
        errors[:cpi] = e
        nil
      end
      wage_rows = begin
        refresh_wages!
      rescue StandardError => e
        errors[:wages] = e
        nil
      end
      Result.new(cpi_years: cpi_years, wage_rows: wage_rows, errors: errors)
    end

    # Merges fetched annual averages over whatever is already on file, so a
    # 10-year API window never shrinks the series the seed started.
    def refresh_cpi!
      merged = Cpi.current.then { |cpi| (2015..Date.current.year).filter_map { |y| v = cpi.value_for(y); [ y, v ] if v }.to_h }
      merged.merge!(fetched_cpi_values)
      raise Datasets::Error, "BLS returned no annual averages" if merged.empty?

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
      raise Datasets::Error, "The OES workbook had no detailed occupation rows" if detailed.empty?

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
        unless response["status"] == "REQUEST_SUCCEEDED"
          raise Datasets::Error, "BLS API: #{Array(response["message"]).join("; ").presence || response["status"]}"
        end

        entries = response.dig("Results", "series", 0, "data") || []
        entries.select { |entry| entry["period"] == "M13" }
          .to_h { |entry| [ entry["year"].to_i, entry["value"].to_f ] }
      end

      def post_json(uri, body)
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "User-Agent" => USER_AGENT)
        request.body = body
        response = http_for(uri).request(request)
        raise Datasets::Error, "BLS API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      # BLS publishes the national file for a May reference period the
      # *following* spring, so the current year's file never exists yet;
      # walk back from last year's until one answers.
      def download_latest_oes
        failures = []
        oes_candidates.each do |year, uri|
          return [ year, download(uri) ]
        rescue StandardError => e
          failures << [ uri, e.message ]
        end
        raise Datasets::Error, oes_failure_message(failures)
      end

      def oes_candidates
        years = (1..OES_VINTAGES).map { |back| Date.current.year - back }
        years.flat_map { |year| OES_URLS.map { |template| [ year, URI(format(template, year % 100)) ] } }
      end

      # A uniform 403 across every vintage and both directory spellings is
      # not a missing file: bls.gov's edge is refusing this instance
      # outright, and no amount of retrying fixes it. Say that, and point at
      # the import path that works from any machine that can reach BLS.
      def oes_failure_message(failures)
        if failures.any? && failures.all? { |_uri, message| message.include?("403") }
          "bls.gov refused every request with HTTP 403 — its edge blocks some clients and networks outright, " \
          "so this instance can't fetch the OES file. Download the OES national zip elsewhere and use " \
          "Import file on /admin instead."
        else
          "No OES national file reachable (#{failures.map { |uri, message| "#{uri}: #{message}" }.join("; ")})"
        end
      end

      def download(uri, redirects: MAX_REDIRECTS)
        tempfile = Tempfile.new([ "oes", ".zip" ])
        tempfile.binmode
        redirect = nil

        http_for(uri).request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT)) do |response|
          if response.is_a?(Net::HTTPRedirection) && response["location"].present?
            redirect = URI.join(uri, response["location"])
            next
          end
          raise Datasets::Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          bytes = 0
          response.read_body do |chunk|
            bytes += chunk.bytesize
            raise Datasets::Error, "download exceeded #{MAX_DOWNLOAD_BYTES / 1.megabyte}MB" if bytes > MAX_DOWNLOAD_BYTES

            tempfile.write(chunk)
          end
        end

        if redirect
          raise Datasets::Error, "too many redirects" if redirects.zero?

          tempfile.close!
          return download(redirect, redirects: redirects - 1)
        end

        tempfile.flush
        tempfile
      rescue StandardError
        tempfile&.close!
        raise
      end

      def http_for(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
        end
      end
  end
end
