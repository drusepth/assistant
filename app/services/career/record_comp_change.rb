module Career
  # After a pay stub is analyzed: if the pay rate (or, for salaried stubs,
  # the per-period gross) moved against the user's previous stub from the
  # same job, land the change on the comp timeline automatically with its
  # provenance named. Pure code over extracted facts — no model call decides
  # anything here (D20), and a first stub with nothing to compare against
  # logs nothing: a level is not a change.
  class RecordCompChange
    def initialize(document)
      @document = document
      @user = document.user
    end

    def call
      stub = PayStub.for(@document)
      return unless stub

      previous = previous_stub(stub)
      return unless previous&.comparable_to?(stub)

      summary = described_change(previous, stub)
      return unless summary
      return if CompChange.scope(@user).exists?(title: "#{CompChange::EVENT_PREFIX} #{summary}")

      CompChange.log!(
        user: @user, summary: summary, on: stub.logged_on,
        description: "Noticed automatically from the pay stub “#{@document.title}”. " \
                     "Edit or delete this if it isn't right — your word beats the parser's."
      )
    end

    private
      def previous_stub(stub)
        PayStub.scope(@user).where.not(id: @document.id)
          .filter_map { |document| PayStub.for(document) }
          .select { |other| other.logged_on <= stub.logged_on }
          .max_by(&:logged_on)
      end

      def described_change(previous, current)
        if previous.rate && current.rate
          "#{money(previous.rate)} → #{money(current.rate)}/hr" unless previous.rate == current.rate
        elsif previous.gross && current.gross && same_cadence?(previous, current)
          "gross #{money(previous.gross)} → #{money(current.gross)} per pay period" unless previous.gross == current.gross
        end
      end

      # Weekly-vs-biweekly stubs would show a gross "change" that is only a
      # calendar artifact; compare gross only when the periods match (or
      # neither stub states its period).
      def same_cadence?(previous, current)
        previous.period_days.nil? || current.period_days.nil? || previous.period_days == current.period_days
      end

      def money(value)
        ActiveSupport::NumberHelper.number_to_currency(value)
      end
  end
end
