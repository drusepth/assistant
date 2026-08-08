module Career
  # A document's extracted pay-stub facts (`documents.extracted_facts["pay_stub"]`,
  # written by Documents::Analyze) behind the tolerant numeric parsing every
  # consumer needs: the model copies numbers as printed, so "$1,234.50" and
  # "1234.5" must read the same. Amounts come back as BigDecimal — this is money.
  class PayStub
    def self.for(document)
      new(document) if document.extracted_facts&.dig("pay_stub").present?
    end

    # Documents that carry pay-stub facts, oldest first — the raw comp
    # timeline before any Events are derived from it.
    def self.scope(user)
      Document.where(user: user).where("json_extract(extracted_facts, '$.pay_stub') IS NOT NULL")
    end

    # The user's nearest earlier stub — what a stub is measured against.
    def self.previous_for(stub)
      scope(stub.document.user).where.not(id: stub.document.id)
        .filter_map { |document| PayStub.for(document) }
        .select { |other| other.logged_on <= stub.logged_on }
        .max_by(&:logged_on)
    end

    def initialize(document)
      @document = document
      @facts = document.extracted_facts.fetch("pay_stub", {})
    end

    attr_reader :document

    def employer = @facts["employer"].to_s.squish.presence
    def pay_date = parse_date(@facts["pay_date"])
    def rate = amount(@facts["rate"])
    def hours = amount(@facts["hours"])
    def overtime_hours = amount(@facts["overtime_hours"])
    def gross = amount(@facts["gross"])
    def net = amount(@facts["net"])

    # [label, amount] pairs; amount nil when the stub printed something unreadable.
    def deductions
      Array(@facts["deductions"]).filter_map do |deduction|
        next unless deduction.is_a?(Hash) && deduction["label"].present?

        [ deduction["label"].to_s.squish, amount(deduction["amount"]) ]
      end
    end

    # The date this stub sorts by on the timeline.
    def logged_on = pay_date || document.created_at.to_date

    def period_days
      from = parse_date(@facts["period_start"])
      to = parse_date(@facts["period_end"])
      (to - from).to_i + 1 if from && to && to >= from
    end

    # Stubs are only comparable within one job: same employer, or neither
    # stub naming one (the single-employer common case).
    def comparable_to?(other)
      if employer.present? || other.employer.present?
        employer.present? && other.employer.present? && employer.casecmp?(other.employer)
      else
        true
      end
    end

    private
      def amount(value)
        cleaned = value.to_s.gsub(/[$,\s]/, "")
        BigDecimal(cleaned) if cleaned.match?(/\A-?\d+(\.\d+)?\z/)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
