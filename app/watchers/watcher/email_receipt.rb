module Watcher
  # Receipts in the mailbox become ledger rows — but only by a click
  # (docs/MONEY.md §2.1, resolving the EMAIL_PLAN §10 parked item). This is
  # the mirror-to-mirror path the D-mirror-layer design anticipated: mail
  # the user's own triage already labeled a receipt, read deterministically
  # (`Spending::Receipt` — no model call), proposed as a suggestion whose
  # accept logs the transaction. Nothing writes itself: a purchase the app
  # invented would poison every meter downstream.
  #
  # Sectionless like the other email watchers — mail is a source, not a
  # section (D-email-monitoring) — and it only speaks for people who have
  # both a mailbox and a ledger: the receipt is only worth logging if
  # there's something to log it into.
  class EmailReceipt < Base
    self.section_slugs = []

    LOOKBACK = 21.days
    SCAN_LIMIT = 200

    def scan
      return unless ledger?

      candidates.each do |message, reading|
        next if already_in_ledger?(reading)

        propose(
          fingerprint: "message:#{message.message_id}",
          kind: :insight,
          title: "Log #{amount(reading.amount_cents)} at #{reading.merchant}?",
          body: "A receipt from #{message.from_name.presence || message.from_email} on " \
                "#{reading.occurred_on.strftime("%B %-d")} — “#{message.subject.presence || "(no subject)"}”. " \
                "If this isn't on a statement you've imported, logging it keeps the month honest.",
          action: {
            "spending" => {
              "amount_cents" => reading.amount_cents,
              "merchant" => reading.merchant,
              "occurred_on" => reading.occurred_on.iso8601,
              "descriptor" => message.subject.to_s.first(120).presence || reading.merchant
            },
            "accept_label" => "Log it"
          },
          sections: %w[ money ]
        )
      end
    end

    private
      def ledger?
        SpendingAccount.where(user_id: user.id).exists?
      end

      def candidates
        EmailMessage.where(user_id: user.id)
          .where("json_extract(triage, '$.category') = 'receipt'")
          .where(sent_at: LOOKBACK.ago..)
          .order(sent_at: :desc).limit(SCAN_LIMIT)
          .filter_map do |message|
            reading = Spending::Receipt.read(message)
            [ message, reading ] if reading
          end
      end

      # A receipt for a purchase already imported from a statement is
      # noise — same amount, same few days is close enough to stay quiet.
      def already_in_ledger?(reading)
        SpendingTransaction.where(user_id: user.id, amount_cents: reading.amount_cents)
          .where(occurred_on: (reading.occurred_on - 3)..(reading.occurred_on + 3))
          .exists?
      end

      def amount(cents) = "#{format("%.2f", cents.abs / 100.0)} #{user.household.currency}"
  end
end
