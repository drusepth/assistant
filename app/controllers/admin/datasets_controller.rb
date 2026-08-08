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
      when ".csv" then import_cpi(file)
      when ".zip", ".xlsx" then import_wages(file)
      when ".txt" then import_common_passwords(file)
      else
        redirect_to admin_root_path,
          alert: "Use the BLS files (the OES national .zip/.xlsx, or a year,value .csv for CPI), or a one-per-line .txt of common passwords."
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

      def import_cpi(file)
        rows = CSV.parse(file.read, headers: true)
        unless rows.headers.map(&:to_s).map(&:strip) == %w[ year value ]
          return redirect_to admin_root_path, alert: "A CPI import needs exactly the headers: year,value."
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
