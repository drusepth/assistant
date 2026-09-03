module Landing
  # A purchase the document records — the vet bill, a receipt, an invoice
  # marked paid — onto the ledger's Cash account, exactly as a quick-logged
  # row lands (MONEY.md §2.1). One write for every path that logs a purchase
  # from something read rather than typed: the email-receipt suggestion
  # (Suggestion#materialize) calls `log!` too.
  class Spending < Base
    self.description = "money the reader paid, as a receipt, bill or invoice states it — the total actually charged, not an estimate or a quote"
    self.produces = "spending_transactions"

    field :amount, "the total paid, as printed, in the household's currency", type: :decimal, required: true
    field :occurred_on, "the date it was paid", type: :date, required: true
    field :merchant, "who was paid, as printed", required: true
    field :descriptor, "what it was for, in a few words"

    def self.label = "spending"

    def land!(attributes, sections:)
      self.class.log!(user,
        amount_cents: -(BigDecimal(attributes["amount"]) * 100).round,
        occurred_on: Date.iso8601(attributes["occurred_on"]),
        merchant: attributes["merchant"], descriptor: attributes["descriptor"].presence || attributes["merchant"],
        source: "document")
    end

    # The shared write: a row on the Cash account, categorized by the
    # deterministic pass. `source` names which reader produced it.
    def self.log!(user, amount_cents:, occurred_on:, merchant:, descriptor:, source:)
      account = ::Spending::QuickLog.cash_account(user)
      row = SpendingTransaction.create!(
        user_id: user.id, spending_account_id: account.id,
        occurred_on: occurred_on, amount_cents: amount_cents,
        descriptor: descriptor, merchant: merchant,
        fingerprint: "#{source}-#{SecureRandom.hex(10)}", source: source)
      ::Spending::Categorize.new(user: user).apply_deterministic
      row
    end

    def duplicate_of(attributes)
      on = parsed_date(attributes["occurred_on"]) or return nil
      cents = -(BigDecimal(attributes["amount"].to_s) * 100).round

      SpendingTransaction.where(user_id: user.id, occurred_on: on, amount_cents: cents).first
    rescue ArgumentError
      nil
    end

    def preview(attributes)
      amount = ActiveSupport::NumberHelper.number_to_currency(attributes["amount"].to_s) rescue attributes["amount"]
      Preview.new(kind: kind, title: "#{amount} — #{attributes["merchant"]}", detail: attributes["descriptor"], date: attributes["occurred_on"])
    end

    private
      def key_fields = %w[ merchant occurred_on amount ]
  end
end
