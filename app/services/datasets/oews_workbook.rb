require "zip"
require "rexml/parsers/streamparser"
require "rexml/streamlistener"

module Datasets
  # Minimal reader for the BLS OES/OEWS national workbook (an .xlsx, alone
  # or inside the published .zip) — just enough spreadsheet to pull
  # occupation codes, titles, and median wages out of a known-shape file.
  # Streaming, so the multi-megabyte sheet never becomes a DOM.
  class OewsWorkbook
    WANTED = {
      "OCC_CODE" => :code, "OCC_TITLE" => :title, "O_GROUP" => :group,
      "H_MEDIAN" => :hourly_median, "A_MEDIAN" => :annual_median
    }.freeze

    Row = Data.define(:code, :title, :group, :hourly_median, :annual_median)

    def self.parse(path)
      new.parse(path)
    end

    # Returns [rows, vintage] — vintage like "May 2024", read from the
    # workbook's filename (BLS names them national_M2024_dl.xlsx).
    def parse(path)
      xlsx_entry = nil
      Zip::File.open(path) do |zip|
        if zip.find_entry("xl/workbook.xml")
          return parse_workbook(zip, vintage_from(path.to_s))
        end

        xlsx_entry = zip.glob("**/*.xlsx").min_by { |entry| entry.name.length }
        raise ArgumentError, "No .xlsx found inside that zip." unless xlsx_entry

        Tempfile.create([ "oews", ".xlsx" ]) do |tempfile|
          tempfile.binmode
          tempfile.write(xlsx_entry.get_input_stream.read)
          tempfile.flush
          Zip::File.open(tempfile.path) do |inner|
            return parse_workbook(inner, vintage_from(xlsx_entry.name))
          end
        end
      end
    end

    private
      def parse_workbook(zip, vintage)
        strings = shared_strings(zip)
        sheet = zip.glob("xl/worksheets/sheet*.xml").min_by(&:name)
        raise ArgumentError, "That file has no worksheet." unless sheet

        listener = SheetListener.new(strings)
        REXML::Parsers::StreamParser.new(sheet.get_input_stream.read, listener).parse
        [ listener.rows, vintage ]
      end

      def shared_strings(zip)
        entry = zip.find_entry("xl/sharedStrings.xml")
        return [] unless entry

        strings = []
        listener = StringsListener.new(strings)
        REXML::Parsers::StreamParser.new(entry.get_input_stream.read, listener).parse
        strings
      end

      def vintage_from(name)
        match = name.match(/M(\d{4})/i)
        match ? "May #{match[1]}" : nil
      end

      # Collects <si> texts (plain or rich-text runs) into one string each.
      class StringsListener
        include REXML::StreamListener

        def initialize(strings)
          @strings = strings
          @in_text = false
        end

        def tag_start(name, _attrs)
          case name
          when "si" then @current = +""
          when "t" then @in_text = true
          end
        end

        def text(value)
          @current << value if @in_text && @current
        end

        def tag_end(name)
          case name
          when "t" then @in_text = false
          when "si" then @strings << @current
          end
        end
      end

      # Walks rows/cells, resolves shared strings, and keeps the wanted
      # columns keyed off the header row.
      class SheetListener
        include REXML::StreamListener

        attr_reader :rows

        def initialize(strings)
          @strings = strings
          @rows = []
          @columns = nil
          @in_value = false
        end

        def tag_start(name, attrs)
          case name
          when "row" then @cells = {}
          when "c"
            @cell_column = attrs["r"].to_s[/\A[A-Z]+/]
            @cell_type = attrs["t"]
          when "v" then @in_value = true
          end
        end

        def text(value)
          return unless @in_value

          resolved = @cell_type == "s" ? @strings[value.to_i] : value
          @cells[@cell_column] = resolved.to_s
        end

        def tag_end(name)
          case name
          when "v" then @in_value = false
          when "row" then finish_row
          end
        end

        private
          def finish_row
            if @columns.nil?
              headers = @cells.transform_values { |v| v.to_s.strip.upcase }
              @columns = headers.filter_map { |column, header| [ column, WANTED[header] ] if WANTED[header] }.to_h
              @columns = nil unless @columns.values.include?(:code)
              return
            end

            fields = @columns.to_h { |column, key| [ key, @cells[column] ] }
            return if fields[:code].blank?

            @rows << Row.new(
              code: fields[:code].to_s.strip,
              title: fields[:title].to_s.strip,
              group: fields[:group].to_s.strip.downcase,
              hourly_median: numeric(fields[:hourly_median]),
              annual_median: numeric(fields[:annual_median])
            )
          end

          # BLS marks unavailable medians "*" and top-coded ones "#"; both
          # read as no-number here, never as zero.
          def numeric(value)
            cleaned = value.to_s.delete(",").strip
            cleaned.to_f if cleaned.match?(/\A\d+(\.\d+)?\z/)
          end
      end
  end
end
