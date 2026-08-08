require "test_helper"

# A dataset refresh fails where nobody is looking — in a job, minutes after the
# admin pressed the button — so the only thing standing between a 403 from
# bls.gov and silence is this job writing it down.
class RefreshDatasetsJobTest < ActiveJob::TestCase
  setup do
    @store_dir = Dir.mktmpdir
    Datasets.store_dir = Pathname(@store_dir)
  end

  teardown do
    Datasets.store_dir = Rails.root.join("storage/datasets")
    FileUtils.remove_entry(@store_dir)
  end

  test "each failed dataset lands in the error log under its own source" do
    stub_request(:post, "https://api.bls.gov/publicAPI/v2/timeseries/data/").to_return(status: 503)
    stub_request(:get, /bls\.gov\/oes/).to_return(status: 403)

    RefreshDatasetsJob.perform_now

    sources = AppError.pluck(:source)
    assert_includes sources, "dataset_refresh:cpi"
    assert_includes sources, "dataset_refresh:wages"

    wages = AppError.find_by(source: "dataset_refresh:wages")
    assert_equal "Datasets::Error", wages.error_class, "the real class survives, not a bare StandardError"
    assert_match(/403/, wages.message)
    assert wages.backtrace.present?, "a recorded failure keeps its backtrace"
  end

  test "one source being down does not stop the other from refreshing" do
    stub_request(:post, "https://api.bls.gov/publicAPI/v2/timeseries/data/").to_return(
      status: 200,
      body: { status: "REQUEST_SUCCEEDED",
              Results: { series: [ { data: [ { year: "2025", period: "M13", value: "322.132" } ] } ] } }.to_json
    )
    stub_request(:get, /bls\.gov\/oes/).to_return(status: 403)

    RefreshDatasetsJob.perform_now

    assert_equal 2025, Datasets::Cpi.current.latest_year
    assert_equal [ "dataset_refresh:wages" ], AppError.pluck(:source)
  end
end
