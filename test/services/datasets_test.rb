require "test_helper"

# The D31 dataset layer: local public data with visible vintage, degrading
# to absence — never to a guess.
class DatasetsTest < ActiveSupport::TestCase
  test "the shipped CPI seed loads and computes drift" do
    cpi = Datasets::Cpi.current

    assert cpi.present?
    assert_operator cpi.latest_year, :>=, 2024
    drift = cpi.drift_since(Date.new(2021, 6, 1))
    assert_in_delta 15.8, drift, 0.5, "CPI-U 2021→2024 is roughly +15.8%"
  end

  test "drift is nil for years off the series or with nothing newer" do
    cpi = Datasets::Cpi.current

    assert_nil cpi.drift_since(Date.new(1990, 1, 1))
    assert_nil cpi.drift_since(Date.new(cpi.latest_year, 6, 1)), "same-year base has nothing newer to compare"
  end

  test "wages are absent until fetched or imported" do
    Tempfile.create([ "empty", ".csv" ]) do
      assert_not Datasets::Wages.new(path: nil).present?
    end
  end

  test "wage search ranks by keyword overlap and reads medians" do
    Tempfile.create([ "wages", ".csv" ]) do |file|
      file.write(<<~CSV)
        occ_code,occ_title,h_median,a_median
        53-7065,Stockers and Order Fillers,17.50,36390
        11-3071,Transportation and Warehousing Managers,,105580
        29-1141,Registered Nurses,45.42,94480
      CSV
      file.flush

      wages = Datasets::Wages.new(path: Pathname(file.path))
      matches = wages.search("warehouse order filler")

      assert_equal "Stockers and Order Fillers", matches.first.title
      assert_equal 17.50, matches.first.hourly_median
      assert_includes matches.map(&:title), "Transportation and Warehousing Managers"
      assert_not_includes matches.map(&:title), "Registered Nurses"
    end
  end

  test "the OES workbook parser reads a minimal xlsx, shared strings and all" do
    Tempfile.create([ "national_M2024_dl", ".xlsx" ]) do |file|
      build_xlsx(file.path)

      rows, vintage = Datasets::OewsWorkbook.parse(Pathname(file.path))

      assert_equal "May 2024", vintage
      detailed = rows.select { |row| row.group == "detailed" }
      assert_equal 1, detailed.size
      assert_equal "53-7065", detailed.first.code
      assert_equal "Stockers and Order Fillers", detailed.first.title
      assert_equal 17.5, detailed.first.hourly_median
      assert_nil rows.last.hourly_median, "a '*' median reads as no number, never zero"
    end
  end

  private
    # The smallest xlsx the parser accepts: shared strings + one sheet with
    # a header row, a detailed occupation, and a suppressed-median row.
    def build_xlsx(path)
      strings = [ "OCC_CODE", "OCC_TITLE", "O_GROUP", "H_MEDIAN", "A_MEDIAN",
                  "53-7065", "Stockers and Order Fillers", "detailed",
                  "00-0000", "All Occupations", "total", "*" ]
      shared = +"<sst>"
      strings.each { |s| shared << "<si><t>#{s}</t></si>" }
      shared << "</sst>"

      sheet = <<~XML
        <worksheet><sheetData>
          <row r="1">
            <c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c>
            <c r="D1" t="s"><v>3</v></c><c r="E1" t="s"><v>4</v></c>
          </row>
          <row r="2">
            <c r="A2" t="s"><v>5</v></c><c r="B2" t="s"><v>6</v></c><c r="C2" t="s"><v>7</v></c>
            <c r="D2"><v>17.5</v></c><c r="E2"><v>36390</v></c>
          </row>
          <row r="3">
            <c r="A3" t="s"><v>8</v></c><c r="B3" t="s"><v>9</v></c><c r="C3" t="s"><v>10</v></c>
            <c r="D3" t="s"><v>11</v></c><c r="E3"><v>49500</v></c>
          </row>
        </sheetData></worksheet>
      XML

      File.delete(path)
      Zip::File.open(path, create: true) do |zip|
        zip.get_output_stream("xl/workbook.xml") { |io| io.write("<workbook/>") }
        zip.get_output_stream("xl/sharedStrings.xml") { |io| io.write(shared) }
        zip.get_output_stream("xl/worksheets/sheet1.xml") { |io| io.write(sheet) }
        zip.get_output_stream("national_M2024_dl.info") { |io| io.write("") }
      end
    end
end
