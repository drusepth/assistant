require "test_helper"

class Admin::DatasetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @store_dir = Dir.mktmpdir
    Datasets.store_dir = Pathname(@store_dir)
  end

  teardown do
    Datasets.store_dir = Rails.root.join("storage/datasets")
    FileUtils.remove_entry(@store_dir)
  end

  test "refresh queues the job" do
    assert_enqueued_with(job: RefreshDatasetsJob) do
      post admin_refresh_datasets_path
    end
    assert_redirected_to admin_root_path
  end

  test "a CPI csv import writes the series into the store" do
    post admin_import_datasets_path, params: {
      file: fixture_file_upload(csv_file("year,value\n2025,320.321\n"), "text/csv")
    }

    assert_redirected_to admin_root_path
    assert_includes Pathname(@store_dir).join("cpi_u.csv").read, "2025,320.321"
    assert_includes Pathname(@store_dir).join("cpi_u.yml").read, "manual import"
    assert_equal 2025, Datasets::Cpi.current.latest_year, "the store now wins over the seed"
  end

  test "a csv with the wrong headers explains" do
    post admin_import_datasets_path, params: {
      file: fixture_file_upload(csv_file("annum,index\n2025,1\n"), "text/csv")
    }

    assert_match(/year,value/, flash[:alert])
  end

  test "an unrecognized extension explains" do
    post admin_import_datasets_path, params: {
      file: fixture_file_upload(csv_file("hello", extension: ".pdf"), "application/pdf")
    }

    assert_match(/BLS files/, flash[:alert])
  end

  # The vault health check's list (PASSWORDS_PLAN W4) rides the same
  # air-gapped import path — one password per line, zero egress.
  test "a txt file imports the common-passwords list" do
    post admin_import_datasets_path, params: {
      file: fixture_file_upload(csv_file("hunter2\nletmein\n\n", extension: ".txt"), "text/plain")
    }

    assert_match(/2 entries/, flash[:notice])
    assert_equal "hunter2\nletmein\n", Datasets.read_path(Vault::Health::DATASET).read
  end

  private
    def csv_file(content, extension: ".csv")
      file = Tempfile.new([ "import", extension ])
      file.write(content)
      file.flush
      file.path
    end
end
