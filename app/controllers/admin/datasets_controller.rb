module Admin
  # The D31 dataset controls: fetch from BLS when the network allows, or
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
      else
        redirect_to admin_root_path,
          alert: "Use the BLS files: the OES national .zip/.xlsx, or a year,value .csv for CPI."
      end
    end

    private
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
