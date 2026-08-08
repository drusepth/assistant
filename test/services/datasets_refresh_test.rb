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

    assert_raises(Datasets::Error) { Datasets::Refresh.new.refresh_cpi! }
    assert_not Pathname(@store_dir).join("cpi_u.csv").exist?
  end

  test "requests identify the instance — bls.gov 403s a default Ruby user agent" do
    stub = stub_request(:post, "https://api.bls.gov/publicAPI/v2/timeseries/data/")
      .with(headers: { "User-Agent" => Datasets::Refresh::USER_AGENT })
      .to_return(status: 200, body: { status: "REQUEST_SUCCEEDED",
        Results: { series: [ { data: [ { year: "2025", period: "M13", value: "322.132" } ] } ] } }.to_json)

    Datasets::Refresh.new.refresh_cpi!

    assert_requested stub
  end

  test "the wage fetch tries both spellings of the BLS directory, newest vintage first" do
    stub_request(:get, /bls\.gov\/oes/).to_return(status: 404)

    error = assert_raises(Datasets::Error) { Datasets::Refresh.new.refresh_wages! }

    last_year = Date.current.year - 1
    assert_requested :get, "https://www.bls.gov/oes/special.requests/oesm#{last_year % 100}nat.zip",
      headers: { "User-Agent" => Datasets::Refresh::USER_AGENT }
    assert_requested :get, "https://www.bls.gov/oes/special-requests/oesm#{last_year % 100}nat.zip"
    # The current year's file is published the following spring — never fetched.
    assert_not_requested :get, "https://www.bls.gov/oes/special.requests/oesm#{Date.current.year % 100}nat.zip"
    assert_match(/No OES national file reachable/, error.message)
  end

  test "a blanket 403 is reported as a blocked instance, not a missing file" do
    stub_request(:get, /bls\.gov\/oes/).to_return(status: 403)

    error = assert_raises(Datasets::Error) { Datasets::Refresh.new.refresh_wages! }

    assert_match(/refused every request with HTTP 403/, error.message)
    assert_match(/Import file/, error.message, "the message names the way out")
  end

  test "the wage download follows a redirect" do
    moved = "https://www.bls.gov/oes/special.requests/oesm#{(Date.current.year - 1) % 100}nat.zip"
    stub_request(:get, /bls\.gov\/oes/).to_return(status: 404)
    stub_request(:get, moved).to_return(status: 302, headers: { "Location" => "https://www.bls.gov/oes/moved.zip" })
    stub_request(:get, "https://www.bls.gov/oes/moved.zip").to_return(status: 200, body: oews_zip)

    rows = Datasets::Refresh.new.refresh_wages!

    assert_equal 1, rows
    assert_equal "May 2025", Datasets::Wages.current.as_of
    assert_includes Pathname(@store_dir).join("oews_national.csv").read, "Registered Nurses"
  end

  test "call collects the exceptions themselves so the error log keeps the class" do
    stub_request(:post, "https://api.bls.gov/publicAPI/v2/timeseries/data/").to_return(status: 503)
    stub_request(:get, /bls\.gov\/oes/).to_return(status: 403)

    result = Datasets::Refresh.new.call

    assert_equal %i[ cpi wages ], result.errors.keys
    assert result.errors.values.all? { |error| error.is_a?(Datasets::Error) }
  end

  private
    # A one-row OES workbook, zipped the way BLS publishes it.
    def oews_zip
      sheet = <<~XML
        <?xml version="1.0"?>
        <worksheet><sheetData>
          <row><c r="A1" t="inlineStr"><v>OCC_CODE</v></c><c r="B1"><v>OCC_TITLE</v></c><c r="C1"><v>O_GROUP</v></c><c r="D1"><v>H_MEDIAN</v></c><c r="E1"><v>A_MEDIAN</v></c></row>
          <row><c r="A2"><v>29-1141</v></c><c r="B2"><v>Registered Nurses</v></c><c r="C2"><v>detailed</v></c><c r="D2"><v>41.38</v></c><c r="E2"><v>86070</v></c></row>
        </sheetData></worksheet>
      XML

      buffer = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("national_M2025_dl.xlsx")
        zip.write(inner_xlsx(sheet))
      end
      buffer.string
    end

    def inner_xlsx(sheet)
      Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("xl/workbook.xml")
        zip.write("<workbook/>")
        zip.put_next_entry("xl/worksheets/sheet1.xml")
        zip.write(sheet)
      end.string
    end
end
