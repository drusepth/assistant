module Admin
  # The D-public-datasets dataset controls: fetch from BLS when the network allows, or
  # import the downloaded files by hand on an air-gapped install. Both paths
  # land in storage/datasets/ and win over the shipped seeds.
  class DatasetsController < BaseController
    def refresh
      RefreshDatasetsJob.perform_later
      redirect_to admin_root_path, notice: "Dataset refresh queued — check back in a minute (errors land in the log below)."
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
      rescue CSV::MalformedCSVError
        redirect_to admin_root_path, alert: "That CSV couldn't be read."
      end

      def import_wages(file)
        Tempfile.create([ "oes-import", File.extname(file.original_filename) ]) do |tempfile|
          tempfile.binmode
          tempfile.write(file.read)
          tempfile.flush
          rows, vintage = Datasets::OewsWorkbook.parse(Pathname(tempfile.path))
          detailed = rows.select { |row| row.group == "detailed" }
          if detailed.empty?
            return redirect_to admin_root_path, alert: "No detailed occupation rows found — is this the OES national file?"
          end

          Datasets::Refresh.new.write_wages!(detailed, vintage || "unknown vintage", source: "manual import")
          redirect_to admin_root_path, notice: "Wage table imported — #{detailed.size} occupations (#{vintage})."
        end
      rescue ArgumentError, Zip::Error => e
        redirect_to admin_root_path, alert: "That file couldn't be read: #{e.message}"
      end
  end
end
