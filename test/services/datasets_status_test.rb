require "test_helper"

# The /admin card's own read of the datasets: what is loaded, and whether the
# last attempt to get it failed.
class DatasetsStatusTest < ActiveSupport::TestCase
  setup do
    @store_dir = Dir.mktmpdir
    Datasets.store_dir = Pathname(@store_dir)
  end

  teardown do
    Datasets.store_dir = Rails.root.join("storage/datasets")
    FileUtils.remove_entry(@store_dir)
  end

  test "reports the seeded CPI series and its source" do
    entry = Datasets::Status.cpi

    assert entry.loaded?
    assert_not entry.failed?
    assert_match(/annual averages through/, entry.summary)
  end

  test "surfaces a failed fetch on the dataset it failed for" do
    AppError.record(Datasets::Error.new("bls.gov refused every request with HTTP 403"),
      source: "dataset_refresh:wages")

    assert_not Datasets::Status.cpi.failed?, "a wage failure is not a CPI failure"

    wages = Datasets::Status.wages
    assert wages.failed?
    assert_equal "fetch", wages.failed_action
    assert_match(/403/, wages.error.message)
  end

  test "an import failure is named as an import" do
    AppError.record(Datasets::Error.new("That file couldn't be read"), source: "dataset_import:cpi")

    assert_equal "import", Datasets::Status.cpi.failed_action
  end

  test "a failure older than the data itself is history, not news" do
    AppError.record(Datasets::Error.new("HTTP 403"), source: "dataset_refresh:wages")
    travel_to 1.hour.from_now do
      Datasets::Refresh.new.write_wages!(
        [ Datasets::OewsWorkbook::Row.new(code: "29-1141", title: "Registered Nurses",
            group: "detailed", hourly_median: 41.38, annual_median: 86_070.0) ],
        "May 2025", source: "manual import"
      )

      entry = Datasets::Status.wages
      assert entry.loaded?
      assert_not entry.failed?, "the fetch that failed before the import no longer applies"
      assert_equal "manual import", entry.source
      assert entry.refreshed_at.present?
    end
  end

  test "a mangled sidecar leaves the dataset readable" do
    Datasets.write!("oews_national.csv", "occ_code,occ_title,h_median,a_median\n29-1141,Registered Nurses,41.38,86070\n")
    Datasets.write!(Datasets::Wages::META_FILENAME, "\tnot: [valid yaml")

    entry = Datasets::Status.wages

    assert entry.loaded?
    assert_nil entry.refreshed_at
  end
end
