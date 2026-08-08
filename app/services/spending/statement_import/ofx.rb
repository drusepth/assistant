# OFX/QFX — the format banks emit for Quicken et al. Parsed by hand with
# the same plain-stdlib discipline as Dav::Client: OFX 1.x is SGML whose
# tags often never close, so this scans <STMTTRN> blocks and pulls tag
# values line-wise rather than pretending it's XML. FITID is the bank's
# own transaction id — the best dedupe key we'll ever get.
class Spending::StatementImport::Ofx
  def self.handles?(filename, content)
    filename.match?(/\.(ofx|qfx)\z/i) ||
      content.lstrip.start_with?("OFXHEADER") ||
      content.include?("<OFX>") || content.include?("<OFX ")
  end

  def self.build(content, account:) = new(content)

  def initialize(content)
    @content = content
  end

  def rows
    @content.scan(%r{<STMTTRN>(.*?)(?=</STMTTRN>|<STMTTRN>|\z)}mi).filter_map do |(block)|
      occurred_on = parse_date(field(block, "DTPOSTED"))
      cents = Spending::StatementImport.parse_cents(field(block, "TRNAMT"))
      next unless occurred_on && cents

      descriptor = [ field(block, "NAME"), field(block, "MEMO") ]
        .map { |part| part.to_s.strip }.reject(&:blank?).uniq.join(" — ")

      Spending::StatementImport::Row.new(
        occurred_on: occurred_on,
        amount_cents: cents,
        descriptor: descriptor.presence || "Transaction",
        external_id: field(block, "FITID"))
    end
  end

  private
    def field(block, tag)
      block[/<#{tag}>([^\r\n<]*)/i, 1]&.strip
    end

    # DTPOSTED arrives as YYYYMMDD, usually with time and timezone junk
    # appended; the first eight digits are the date.
    def parse_date(raw)
      digits = raw.to_s[/\A\d{8}/] or return nil
      Date.strptime(digits, "%Y%m%d")
    rescue Date::Error
      nil
    end
end
