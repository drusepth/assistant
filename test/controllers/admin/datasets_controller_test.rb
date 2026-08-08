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
      file: fixture_file_upload(csv_file("hello", extension: ".txt"), "text/plain")
    }

    assert_match(/BLS files/, flash[:alert])
  end

  test "a file that isn't a workbook explains and lands in the error log" do
    post admin_import_datasets_path, params: {
      file: fixture_file_upload(csv_file("not a zip at all", extension: ".zip"), "application/zip")
    }

    assert_redirected_to admin_root_path
    assert_match(/couldn't be read/, flash[:alert])
    assert_match(/Nothing was changed/, flash[:alert])

    error = AppError.find_by(source: "dataset_import:wages")
    assert error.present?, "an import that dies on a bad file is recorded, not swallowed"
    assert_equal users(:one), error.user
  end

  test "a malformed CPI csv explains and is recorded" do
    post admin_import_datasets_path, params: {
      file: fixture_file_upload(csv_file(%(year,value\n2025,"320), extension: ".csv"), "text/csv")
    }

    assert_match(/malformed/, flash[:alert])
    assert AppError.exists?(source: "dataset_import:cpi")
  end

  test "the admin card names a failed fetch in place" do
    AppError.record(Datasets::Error.new("bls.gov refused every request with HTTP 403"),
      source: "dataset_refresh:wages")

    get admin_root_path

    assert_response :success
    assert_match(/Last fetch failed/, response.body)
    assert_match(/refused every request with HTTP 403/, response.body)
  end

  private
    def csv_file(content, extension: ".csv")
      file = Tempfile.new([ "import", extension ])
      file.write(content)
      file.flush
      file.path
    end
end
