module Sections
  module Panels
    # The Budget subsection panel (D-budget-envelopes, docs/MONEY.md §3.3):
    # the envelope board — per-category meters over the current month,
    # inline target editing, quick-log capture, and the empty state as
    # front door (no categories → Build my budget leads; no ledger → the
    # import invitation leads). No signal, no shame: an empty budget page
    # invites, never scolds.
    class Budget < Panel
      def summary
        @summary ||= ::Money::MonthSummary.new(user: viewer)
      end

      def categories? = summary.categories.any?

      def ledger?
        return @ledger if defined?(@ledger)
        @ledger = SpendingTransaction.where(user_id: viewer.id).exists?
      end

      def uncategorized_count
        @uncategorized_count ||= SpendingTransaction.where(user_id: viewer.id).uncategorized.count
      end

      def hidden_tool_slugs = %w[ build_my_budget ]
    end
  end
end
