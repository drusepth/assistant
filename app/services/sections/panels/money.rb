module Sections
  module Panels
    # The Money lead panel (D-budget-envelopes, docs/MONEY.md §3.3): the
    # money map — this month at a glance over the ledger, quick capture,
    # and the subsection tiles below it with real signal. Everything is
    # derived (Money::MonthSummary holds no state), and everything reads
    # the viewer's own ledger only — there is no visible_to path to the
    # mirror.
    class Money < Panel
      def summary
        @summary ||= ::Money::MonthSummary.new(user: viewer)
      end

      def ledger?
        return @ledger if defined?(@ledger)
        @ledger = SpendingTransaction.where(user_id: viewer.id).exists?
      end

      def uncategorized_count
        @uncategorized_count ||= SpendingTransaction.where(user_id: viewer.id).uncategorized.count
      end

      # The panel carries these with better context than an Act-zone card.
      def hidden_tool_slugs = %w[ build_my_budget ]
    end
  end
end
