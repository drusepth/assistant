# The budget snapshot the coach reasons from (docs/MONEY.md §5.1) —
# code-built from MonthSummary, so every number the coach can cite is one
# the ledger computed. Deliberately compact: this rides in a chat system
# prompt on every turn, and the model-agnostic constraint means small
# local models have to hold it.
class Money::Snapshot
  MAX_LINES = 12

  def initialize(user:)
    @user = user
    @summary = Money::MonthSummary.new(user: user)
  end

  def any? = @summary.categories.any? || @summary.any_activity?

  def to_prompt
    return nil unless any?

    parts = [ header ]
    parts << envelope_block if envelope_block
    parts << "Money in so far this month: #{amount(@summary.income_cents)}" if @summary.income_cents.positive?
    if @summary.unbudgeted_cents.positive?
      parts << "Spending in no envelope yet: #{amount(@summary.unbudgeted_cents)}"
    end
    parts << wage_line if wage_line
    parts.join("\n")
  end

  private
    def header
      pieces = [ "#{@summary.month.strftime("%B")}: spent #{amount(@summary.spent_cents)}" ]
      pieces << "of #{amount(@summary.target_cents)} planned" if @summary.target_cents
      pieces << "with #{@summary.days_left} days left" if @summary.days_left.positive?
      "#{pieces.join(" ")}."
    end

    def envelope_block
      lines = @summary.lines.select { |line| line.target? || line.spent_cents.positive? }.first(MAX_LINES)
      return nil if lines.empty?

      rows = lines.map do |line|
        if line.target?
          state = line.over? ? "over by #{amount(line.spent_cents - line.target_cents)}" :
            "#{amount(line.remaining_cents)} left"
          "- #{line.category.name}: #{amount(line.spent_cents)} of #{amount(line.target_cents)}, #{state}"
        else
          "- #{line.category.name}: #{amount(line.spent_cents)} spent, no target set"
        end
      end
      "Envelopes:\n#{rows.join("\n")}"
    end

    # The hours-of-work frame, only when the comp timeline actually says so
    # (D-career-signal rung 3: no signal, no claim — never an estimate).
    def wage_line
      return @wage_line if defined?(@wage_line)

      latest = Career::CompChange.scope(@user).order(starts_at: :desc).first
      hourly = latest&.title.to_s[/([\d,]+(?:\.\d+)?)\s*(?:\/|per\s*)(?:hr|hour)/i, 1]
      @wage_line = if hourly
        "The user logged an hourly rate of #{hourly} #{currency} (from their own comp timeline, " \
        "#{latest.starts_at.to_date.iso8601}) — you may frame costs as hours of work when it helps. " \
        "Never estimate an hourly rate they did not state."
      end
    end

    def currency = @user.household.currency

    def amount(cents) = "#{(cents / 100.0).round} #{currency}"
end
