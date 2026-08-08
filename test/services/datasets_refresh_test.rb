require "test_helper"

# The fetch half of D31: BLS annual averages merge over what's on file —
# a 10-year API window never shrinks the series the seed started.
class DatasetsRefreshTest < ActiveSupport::TestCase
  setup do
    @store_dir = Dir.mktmpdir
    Datasets.store_dir = Pathname(@store_dir)
  end

  teardown do
    Datasets.store_dir = Rails.root.join("storage/datasets")
    FileUtils.remove_entry(@store_dir)
  end

  test "refresh_cpi! merges fetched annual averages over the seed" do
    stub_request(:post, "https://api.bls.gov/publicAPI/v2/timeseries/data/").to_return(
      status: 200,
      body: {
        status: "REQUEST_SUCCEEDED",
        Results: { series: [ { data: [
          { year: "2025", period: "M13", value: "322.132" },
          { year: "2025", period: "M06", value: "321.500" },
          { year: "2024", period: "M13", value: "313.689" }
        ] } ] }
      }.to_json
    )

    latest = Datasets::Refresh.new.refresh_cpi!

    assert_equal 2025, latest
    cpi = Datasets::Cpi.current
    assert_equal 2025, cpi.latest_year
    assert_in_delta 322.132, cpi.value_for(2025), 0.001
    assert_in_delta 240.007, cpi.value_for(2016), 0.001, "seed years survive the merge"
    assert_includes Pathname(@store_dir).join("cpi_u.yml").read, "api.bls.gov"
  end

  test "a failed API call raises and leaves the files untouched" do
    stub_request(:post, "https://api.bls.gov/publicAPI/v2/timeseries/data/").to_return(status: 503, body: "down")

    assert_raises(RuntimeError) { Datasets::Refresh.new.refresh_cpi! }
    assert_not Pathname(@store_dir).join("cpi_u.csv").exist?
  end
end
