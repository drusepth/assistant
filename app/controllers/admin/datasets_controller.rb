module Admin
  # The D-public-datasets dataset controls: fetch from BLS when the network allows, or
  # import the downloaded files by hand on an air-gapped install. Both paths
  # land in storage/datasets/ and win over the shipped seeds.
  #
  # Both paths also report their failures the same way: a flash for the person
  # standing here, an AppError for the log. An import that dies on a malformed
  # workbook used to leave nothing behind but a flash the next click erased.
  class DatasetsController < BaseController
    def refresh
      RefreshDatasetsJob.perform_later
      redirect_to admin_root_path,
        notice: "Dataset refresh queued — reload in a minute; this page reports whether it worked."
    end

    def import
      file = params[:file]
      return redirect_to admin_root_path, alert: "Pick a file first." if file.blank?

      case File.extname(file.original_filename).downcase
      when ".csv" then import_csv(file)
      when ".zip", ".xlsx" then import_wages(file)
      when ".txt" then import_common_passwords(file)
      else
        redirect_to admin_root_path,
          alert: "Use the BLS files (the OES national .zip/.xlsx, or a year,value .csv for CPI), a #{Datasets::Places::HEADERS.join(",")} .csv of place names, or a one-per-line .txt of common passwords."
      end
    end

    private
      # The vault health check's list (PASSWORDS_PLAN W4): one password per
      # line — e.g. a slice of SecLists' top-N — replacing the small seed.
      # Local file, zero egress; the health page shows the list's size.
      def import_common_passwords(file)
        lines = file.read.force_encoding(Encoding::UTF_8).scrub.split("\n").map(&:strip).reject(&:empty?)
        return redirect_to admin_root_path, alert: "That file was empty." if lines.empty?

        Datasets.write!(Vault::Health::DATASET, lines.join("\n") + "\n")
        redirect_to admin_root_path, notice: "Common-passwords list imported — #{lines.size} entries now checked."
      rescue StandardError => e
        report_failure(:common_passwords, e)
      end

      # Two datasets arrive as CSV, so the headers pick the parser rather
      # than the extension — a places file and a CPI file are not remotely
      # confusable once you have looked at row one.
      def import_csv(file)
        rows = CSV.parse(file.read.force_encoding(Encoding::UTF_8).scrub, headers: true)
        headers = rows.headers.map(&:to_s).map(&:strip)

        if headers.first(5) == Datasets::Places::HEADERS
          import_places(rows)
        else
          import_cpi(rows, headers)
        end
      rescue CSV::MalformedCSVError => e
        report_failure(:cpi, e)
      end

      # The gazetteer the photo map names pins from (docs/TRAVEL.md). Shipped
      # as a seed, replaceable here: an instance that wants the villages
      # Natural Earth's 7,000 settlements miss can drop in a denser file
      # without waiting for a release.
      def import_places(rows)
        places = rows.filter_map do |row|
          latitude = Float(row["latitude"], exception: false)
          longitude = Float(row["longitude"], exception: false)
          next if row["name"].blank? || latitude.nil? || longitude.nil?

          [ row["name"], row["country"], latitude, longitude, row["population"].to_i ]
        end
        if places.empty?
          return redirect_to admin_root_path, alert: "No usable rows in that places file — nothing was changed."
        end

        Datasets.write!(Datasets::Places::FILENAME,
          CSV.generate(write_headers: true, headers: Datasets::Places::HEADERS) { |csv| places.each { |place| csv << place } })
        Datasets.write!(Datasets::Places::META_FILENAME,
          { "source" => "manual import", "places" => places.size, "refreshed_at" => Time.current.iso8601 }.to_yaml)
        Datasets::Places.reset!
        redirect_to admin_root_path, notice: "Place names imported — #{places.size} settlements now name map pins."
      rescue StandardError => e
        report_failure(:places, e)
      end

      def import_cpi(rows, headers)
        unless headers == %w[ year value ]
          return redirect_to admin_root_path,
            alert: "That CSV matched neither dataset: CPI needs year,value and place names need #{Datasets::Places::HEADERS.join(",")}."
        end

        Datasets.write!(Datasets::Cpi::FILENAME, [ "year,value", *rows.map { |r| "#{r["year"].to_i},#{r["value"].to_f}" } ].join("\n") + "\n")
        Datasets.write!("cpi_u.yml", { "series_id" => Datasets::Refresh::CPI_SERIES,
                                       "source" => "manual import", "refreshed_at" => Time.current.iso8601 }.to_yaml)
        redirect_to admin_root_path, notice: "CPI series imported — now through #{Datasets::Cpi.current.latest_year}."
      rescue StandardError => e
        report_failure(:cpi, e)
      end

      def import_wages(file)
        Tempfile.create([ "oes-import", File.extname(file.original_filename) ]) do |tempfile|
          tempfile.binmode
          tempfile.write(file.read)
          tempfile.flush
          rows, vintage = Datasets::OewsWorkbook.parse(Pathname(tempfile.path))
          detailed = rows.select { |row| row.group == "detailed" }
          if detailed.empty?
            raise Datasets::Error, "No detailed occupation rows found — is this the OES national file?"
          end

          Datasets::Refresh.new.write_wages!(detailed, vintage || "unknown vintage", source: "manual import")
          redirect_to admin_root_path, notice: "Wage table imported — #{detailed.size} occupations (#{vintage})."
        end
      rescue StandardError => e
        report_failure(:wages, e)
      end

      # Anything the parser throws — a truncated zip, an .xlsx that is really
      # a renamed .csv, an encoding the sheet reader chokes on — is a file
      # problem the admin can act on, not a 500 to swallow.
      def report_failure(dataset, error)
        AppError.record(error, source: "dataset_import:#{dataset}", user: Current.user)
        redirect_to admin_root_path,
          alert: "That file couldn't be read: #{friendly_message(error)} Nothing was changed."
      end

      def friendly_message(error)
        case error
        when CSV::MalformedCSVError then "the CSV is malformed."
        when Datasets::Error, ArgumentError, Zip::Error then error.message
        else "#{error.class} — the full error is in the log below."
        end
      end
  end
end
