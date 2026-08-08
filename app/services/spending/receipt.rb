# Reading a purchase out of a receipt email (docs/MONEY.md §2.1, the
# parked EMAIL_PLAN follow-on) — deterministically, with no model call.
# Triage already labeled the message a receipt; this only pulls the
# amount and the merchant out of text the user's own mailbox delivered.
# Deliberately strict: an unreadable receipt yields nothing rather than a
# guess, because a wrong number in the ledger is worse than a missing one.
module Spending::Receipt
  # Ordered strongest-first: a labeled total beats a bare currency figure.
  TOTAL_PATTERNS = [
    /(?:order\s+)?total[^\d\n]{0,20}([€£$]?\s?[\d,]+\.\d{2})/i,
    /amount\s+(?:charged|paid|due)[^\d\n]{0,20}([€£$]?\s?[\d,]+\.\d{2})/i,
    /(?:you\s+)?(?:paid|charged)[^\d\n]{0,20}([€£$]?\s?[\d,]+\.\d{2})/i,
    /grand\s+total[^\d\n]{0,20}([€£$]?\s?[\d,]+\.\d{2})/i
  ].freeze

  SCAN_CHARS = 4_000
  MAX_CENTS = 5_000_000 # a five-figure "receipt" is a parse error, not a purchase

  Reading = Data.define(:amount_cents, :merchant, :occurred_on)

  module_function

  # Returns a Reading, or nil when the message doesn't yield one cleanly.
  def read(message)
    return nil unless message.triage&.dig("category") == "receipt"

    cents = total_cents(message) or return nil
    merchant = merchant_for(message) or return nil

    Reading.new(amount_cents: -cents, merchant: merchant,
      occurred_on: (message.sent_at || message.created_at).to_date)
  end

  def total_cents(message)
    text = "#{message.subject}\n#{message.body_text}".to_s.first(SCAN_CHARS)

    TOTAL_PATTERNS.each do |pattern|
      match = text[pattern, 1] or next
      cents = Spending::StatementImport.parse_cents(match)
      return cents.abs if cents&.nonzero? && cents.abs <= MAX_CENTS
    end
    nil
  end

  # The sender's own domain is the honest merchant name — display names in
  # receipt mail are marketing copy ("Your Amazon.com order has shipped"),
  # and the domain is what the user will recognize on a statement.
  def merchant_for(message)
    domain = message.from_email.to_s.split("@").last.to_s.downcase
    return nil if domain.blank?

    label = domain.split(".").reject { |part| part.in?(%w[ com net org co uk io mail email ]) }
      .reject { |part| part.in?(%w[ no-reply noreply reply receipts orders ]) }
      .max_by(&:length)
    label&.upcase.presence
  end
end
