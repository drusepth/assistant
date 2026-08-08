# Deterministic cleanup of card-processor noise so "SQ *BLUE BOTTLE 0921
# OAKLAND CA" and "SQ *BLUE BOTTLE 1104 OAKLAND CA" group as one merchant.
# Conservative on purpose: strip only recognizable prefixes and trailing
# reference junk — a descriptor we can't improve passes through squished,
# never mangled.
module Spending::Normalize
  PREFIXES = /\A(?:
    POS(?:\ (?:DEBIT|PURCHASE))? |
    DEBIT\ CARD\ PURCHASE |
    CHECK\ ?CARD |
    PURCHASE\ AUTHORIZED\ ON\ \d{2}\/\d{2} |
    ACH\ (?:DEBIT|CREDIT|WITHDRAWAL) |
    ELECTRONIC\ (?:PMT|PAYMENT|WITHDRAWAL) |
    RECURRING\ PAYMENT |
    WEB\ PMT |
    CARD\ PURCHASE
  )[\s:,-]+/xi

  PROCESSOR_STARS = /\A(?:SQ|TST|PAR|PY|PP|PAYPAL|AMZN\ MKTP(?:\ [A-Z]{2})?)\s?\*\s?/i

  module_function

  def merchant(descriptor)
    cleaned = descriptor.to_s.squish
    return nil if cleaned.blank?

    stripped = cleaned.sub(PREFIXES, "").sub(PROCESSOR_STARS, "")
    stripped = stripped.sub(/\s*\*\s?[A-Z0-9\-]+\z/i, "")          # trailing star-refs: "NETFLIX *3921"
    stripped = stripped.gsub(/\s+#?\d{4,}(?=\s|\z)/, "")           # store/reference numbers: "BLUE BOTTLE 0921 OAKLAND"
    stripped = stripped.sub(/\s+X{2,}\d*\z/i, "")                  # masked card tails
    stripped = stripped.sub(/\s+\d{2}\/\d{2}(?:\/\d{2,4})?\z/, "") # trailing dates

    stripped.squish.presence || cleaned
  end
end
