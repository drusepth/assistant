module Career
  # The arithmetic every pay stub should get and almost none do — done by
  # code, never the model (docs/CAREER.md §3.3): hours × rate vs gross,
  # overtime that should be there and isn't, a rate drop or a new deduction
  # against the previous stub. Shared by the Check-my-pay-stub tool (the
  # note's "what the numbers say" block) and the stub-anomaly watcher (the
  # nudge's evidence), so both always agree.
  class PayStubAudit
    # Rounding, employer-side "other earnings" lines, and model transcription
    # all wobble by cents; only a real gap is worth the user's alarm.
    TOLERANCE = BigDecimal("1")
    OVERTIME_MULTIPLIER = BigDecimal("1.5")

    def initialize(stub, previous: nil)
      @stub = stub
      @previous = previous || PayStub.previous_for(stub)
      @previous = nil unless @previous&.comparable_to?(stub)
    end

    # Human-readable findings; `concerning` ones point at possible missing pay.
    def findings = checks.map(&:last)

    def concerning_findings = checks.select(&:first).map(&:last)

    def concerning? = checks.any?(&:first)

    private
      def checks
        @checks ||= [ shorted_gross, missing_overtime, rate_drop, *new_deductions ].compact
      end

      def shorted_gross
        return unless @stub.hours && @stub.rate && @stub.gross

        expected = @stub.hours * @stub.rate
        expected += @stub.overtime_hours * @stub.rate * OVERTIME_MULTIPLIER if @stub.overtime_hours
        gap = expected - @stub.gross
        return unless gap > TOLERANCE

        [ true, "The math comes up short: #{@stub.hours.to_i} hours at #{money(@stub.rate)}" \
                "#{" plus overtime" if @stub.overtime_hours} works out to #{money(expected)}, " \
                "but gross pay is #{money(@stub.gross)} — #{money(gap)} missing." ]
      end

      def missing_overtime
        return unless @stub.period_days && @stub.period_days <= 7
        return unless @stub.hours && @stub.hours > 40
        return if @stub.overtime_hours&.positive?

        [ true, "#{@stub.hours.to_i} hours in a one-week period with no overtime line — " \
                "hours past 40 usually earn 1.5× pay." ]
      end

      def rate_drop
        return unless @previous&.rate && @stub.rate
        return unless @stub.rate < @previous.rate

        [ true, "Your rate dropped against the #{@previous.logged_on.strftime("%B %-d")} stub: " \
                "#{money(@previous.rate)} → #{money(@stub.rate)}/hr." ]
      end

      def new_deductions
        return [] unless @previous

        known = @previous.deductions.map { |label, _amount| label.downcase }
        @stub.deductions.reject { |label, _amount| known.include?(label.downcase) }
          .map do |label, amount|
            [ false, "New deduction since the last stub: #{label}#{" (#{money(amount)})" if amount}." ]
          end
      end

      def money(value)
        ActiveSupport::NumberHelper.number_to_currency(value)
      end
  end
end
