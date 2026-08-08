# Bank CSVs disagree about everything, so CSV import rides a per-account
# saved mapping (MONEY.md §2.1): which headers hold the date, description,
# and amount (or separate debit/credit columns), the date format, and
# which sign means money out. The first import from an account raises
# MappingNeeded, which routes the user through the mapping form; the
# saved mapping makes every later import one click.
class Spending::StatementImport::MappedCsv
  class MappingNeeded < StandardError; end

  # Everything the mapping form can save. `sign` covers the banks that
  # print purchases as positive numbers: "negative_out" (default) trusts
  # the sign as written, "positive_out" flips it.
  KEYS = %w[ date description amount debit credit date_format sign ].freeze

  def self.handles?(filename, content)
    filename.match?(/\.csv\z/i) || content.lines.first.to_s.include?(",")
  end

  def self.build(content, account:) = new(content, mapping: account.csv_mapping)

  def initialize(content, mapping:)
    @content = content
    @mapping = (mapping || {}).slice(*KEYS)
  end

  def rows
    raise MappingNeeded unless usable_mapping?

    table = CSV.parse(@content, headers: true, liberal_parsing: true, skip_blanks: true)
    table.filter_map do |row|
      occurred_on = parse_date(row[@mapping["date"]])
      cents = amount_cents(row)
      next unless occurred_on && cents

      Spending::StatementImport::Row.new(
        occurred_on: occurred_on,
        amount_cents: cents,
        descriptor: row[@mapping["description"]].to_s.squish.presence || "Transaction",
        external_id: nil)
    end
  rescue CSV::MalformedCSVError
    []
  end

  private
    def usable_mapping?
      @mapping["date"].present? && @mapping["description"].present? &&
        (@mapping["amount"].present? || @mapping["debit"].present? || @mapping["credit"].present?)
    end

    def parse_date(raw)
      value = raw.to_s.strip
      return nil if value.blank?

      if @mapping["date_format"].present?
        Date.strptime(value, @mapping["date_format"]) rescue nil
      else
        Date.parse(value) rescue nil
      end
    end

    def amount_cents(row)
      if @mapping["amount"].present?
        cents = Spending::StatementImport.parse_cents(row[@mapping["amount"]])
        return nil unless cents
        @mapping["sign"] == "positive_out" ? -cents : cents
      else
        debit = Spending::StatementImport.parse_cents(row[@mapping["debit"]]) if @mapping["debit"].present?
        credit = Spending::StatementImport.parse_cents(row[@mapping["credit"]]) if @mapping["credit"].present?
        return -debit.abs if debit&.nonzero?
        return credit.abs if credit&.nonzero?
        nil
      end
    end
end
