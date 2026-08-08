# Fans a bank-statement file into the spending ledger (D-spending-mirror,
# MONEY.md §2). Modular like People::Import: each format is a parser class
# answering `handles?` and emitting normalized Rows; everything funnels
# through the same dedupe/insert here, so no two paths can disagree. The
# statement itself is an ordinary vault Document created by the caller —
# the durable, exportable artifact this mirror slice rebuilds from.
class Spending::StatementImport
  # What every parser emits. amount_cents is signed: negative = money out.
  Row = Struct.new(:occurred_on, :amount_cents, :descriptor, :external_id, keyword_init: true)

  Result = Struct.new(:imported, :skipped, :error, keyword_init: true)

  # Ordered: the self-describing format first, CSV (which needs a mapping) last.
  FORMATS = [
    Spending::StatementImport::Ofx,
    Spending::StatementImport::MappedCsv
  ].freeze

  def initialize(user:, account:, content:, filename:, document_id: nil)
    @user = user
    @account = account
    @content = normalize_encoding(content.to_s.dup)
    @filename = filename.to_s
    @document_id = document_id
  end

  def call
    parser = FORMATS.find { |format| format.handles?(@filename, @content) }
    unless parser
      return Result.new(imported: 0, skipped: 0,
        error: "That file doesn't look like a bank statement export. Use a CSV or OFX/QFX download from your bank.")
    end

    rows = parser.build(@content, account: @account).rows.select { |row| row.occurred_on && row.amount_cents }
    if rows.empty?
      return Result.new(imported: 0, skipped: 0,
        error: "No transactions found in that file — check it's the transactions export, not a summary.")
    end

    imported = insert(rows)
    Spending::Transfers.pair(@user)
    categorize = Spending::Categorize.new(user: @user)
    categorize.apply_deterministic
    Spending::CategorizeJob.perform_later(@user) if imported.positive?

    Result.new(imported: imported, skipped: rows.size - imported)
  rescue Spending::StatementImport::MappedCsv::MappingNeeded
    Result.new(imported: 0, skipped: 0, error: :mapping_needed)
  end

  private
    # Re-importing an overlapping statement is the normal case: the bank id
    # wins when present, the content fingerprint covers the rest, and
    # tombstones keep deletions deleted. Genuine same-day duplicates (two
    # identical coffees) get a deterministic occurrence suffix, so the same
    # file always fingerprints the same way.
    def insert(rows)
      seen = Hash.new(0)
      existing_external = @account.transactions.where.not(external_id: nil).pluck(:external_id).to_set
      count = 0

      rows.each do |row|
        if row.external_id.present?
          next if existing_external.include?(row.external_id)
          existing_external << row.external_id
        end

        base = SpendingTransaction.fingerprint_for(@account.id, row.occurred_on, row.amount_cents, row.descriptor)
        occurrence = (seen[base] += 1)
        fingerprint = occurrence > 1 ? "#{base}-#{occurrence}" : base

        next if SpendingTombstone.covers?(@account.id, fingerprint)
        next if @account.transactions.exists?(fingerprint: fingerprint)

        SpendingTransaction.create!(
          user_id: @user.id,
          spending_account_id: @account.id,
          occurred_on: row.occurred_on,
          amount_cents: row.amount_cents,
          descriptor: row.descriptor.to_s.squish.presence,
          merchant: Spending::Normalize.merchant(row.descriptor),
          external_id: row.external_id.presence,
          fingerprint: fingerprint,
          document_id: @document_id,
          source: "statement")
        count += 1
      end

      count
    end

    def normalize_encoding(content)
      content.force_encoding(Encoding::UTF_8)
      content.valid_encoding? ? content : content.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
    end

    # "1,234.56", "-12.34", "(45.00)", "$89", "12,34" → signed cents.
    # Shared by the parsers; nil when the string doesn't look like money.
    def self.parse_cents(raw)
      str = raw.to_s.strip
      return nil if str.blank?

      negative = str.include?("(") || str.include?("-")
      digits = str.gsub(/[^\d.,]/, "")
      return nil if digits.blank?

      # When both separators appear, the later one is the decimal point;
      # a lone comma with two trailing digits is one too (European style).
      if digits.include?(".") && digits.include?(",")
        digits = digits.rindex(".") > digits.rindex(",") ? digits.delete(",") : digits.delete(".").tr(",", ".")
      elsif digits.count(",") == 1 && digits =~ /,\d{1,2}\z/
        digits = digits.tr(",", ".")
      else
        digits = digits.delete(",")
      end

      cents = (BigDecimal(digits) * 100).round.to_i
      negative ? -cents : cents
    rescue ArgumentError
      nil
    end
end
