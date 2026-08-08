module Tool
  # The tool that turns "I should really budget" into a budget in two
  # minutes (D-budget-envelopes, docs/MONEY.md §3.2). Two paths, one
  # prompt: with an imported ledger it proposes targets from the user's
  # real averages (code aggregates them — the model never sees raw
  # transaction rows); with a thin ledger it works from three optional
  # intake lines. Re-running it later is "tune my budget" — it reads
  # actuals against targets and proposes adjustments through the same
  # suggest-and-apply gate.
  #
  # Landing follows D17 discipline exactly: envelopes auto-apply, a
  # hand-set target is never overwritten, and pruning is one click.
  class BuildMyBudget < Base
    self.title = "Build my budget"
    self.description = "Turn what you actually spend into monthly envelopes you can live inside."
    self.section_slugs = %w[ budget ]
    self.kind = :draft

    MAX_CATEGORIES = 15
    MAX_TARGET_CENTS = 100_000_000 # a sanity ceiling, not a judgment

    input :take_home, label: "Roughly, your monthly take-home pay",
      hint: "Optional — leave blank and imported deposits speak for themselves."
    input :housing, label: "Rent or mortgage each month",
      hint: "Optional if it's already in your imported spending."
    input :situation, kind: :textarea,
      label: "Anything big going on?",
      hint: "Optional — “new baby”, “paying down cards”, “saving for a deposit”. It shapes the plan."

    Envelope = Data.define(:name, :group, :monthly_target_cents, :why)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the budget-building feature of a private, self-hosted life assistant.
      You turn a person's real spending into monthly envelope targets they can
      actually live inside. The audience is ordinary people, often on tight
      budgets — this is the plan that decides whether the month works, so it must
      be realistic first and aspirational second. A budget the user blows through
      in week two teaches them budgeting doesn't work for them.

      Respond with a JSON object:
      {"budget": {"categories": [{"name": "...", "group": "needs" | "wants" | "savings_debt" | "income",
                                  "monthly_target": 520, "why": "..."}, ...]},
       "summary": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}

      Rules for categories:
      - At most #{MAX_CATEGORIES}, ordered most-important first. Fewer, bigger envelopes beat
        a long tail nobody maintains.
      - monthly_target is a plain number in the user's currency, no symbols or
        separators. Round to something a human would say (520, not 517.43).
      - group: "needs" for the roof-and-lights essentials, "wants" for the
        discretionary, "savings_debt" for saving and debt payoff, "income" for
        expected money in (include at most one income row, only if you know it).
      - Prefer these standard names where they fit, because the assistant
        recognizes them and files transactions into them automatically:
        Groceries, Dining out, Transport, Utilities, Phone & internet,
        Streaming & subscriptions, Housing, Insurance, Health, Income.
      - why: one short clause naming where the number came from — the computed
        average, the user's stated figure, or "starting point, tune after a month".
        This is what makes the budget trustworthy, so never leave it vague.

      Honesty rules, non-negotiable:
      - Every number you propose must come from the computed spending averages
        given to you or from what the user typed. Never invent a figure, and
        never present a guess as if it were measured.
      - When the numbers came from a thin or missing history, say so plainly in
        the summary and mark those targets as starting points.
      - If planned spending exceeds known income, say that directly and kindly in
        the summary — name the gap, do not bury it — and put the savings/debt
        envelope at what's actually left, not at a number that only works on paper.
      - Never moralize about how the person spends. Describe, propose, and let
        them decide.

      The summary body is two or three short paragraphs in plain language: what
      this budget assumes, where the numbers came from, and the one or two places
      the month will be tightest. Do not list the envelopes in the body — they
      are rendered separately.
      follow_ups: at most #{MAX_FOLLOW_UPS} small concrete actions ("import your credit-card
      statement so the picture is complete").
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}", "Currency: #{user.household.currency}" ]

        if aggregates.any?
          parts << aggregates.to_prompt
        else
          parts << "The user has not imported any spending yet — build from what they typed, " \
                   "and treat every target as a starting point to tune after a month of data."
        end

        stated = []
        stated << "Monthly take-home pay: #{inputs[:take_home]}" if inputs[:take_home].present?
        stated << "Rent or mortgage: #{inputs[:housing]}" if inputs[:housing].present?
        stated << "What's going on: #{inputs[:situation]}" if inputs[:situation].present?
        parts << "What the user told us (their word beats the computed averages):\n#{stated.join("\n")}" if stated.any?

        parts << existing_budget_block if existing_budget_block
        parts.join("\n\n")
      end

      # Re-running is "tune my budget": the model sees the current envelopes
      # and this month's actuals against them, and proposes adjustments.
      def existing_budget_block
        return @existing_budget_block if defined?(@existing_budget_block)

        lines = summary.lines.select { |line| line.target? || line.spent_cents.positive? }
        @existing_budget_block =
          if lines.empty?
            nil
          else
            rows = lines.map do |line|
              target = line.target? ? "target #{whole(line.target_cents)}" : "no target"
              hand = line.category.target_hand_set? ? ", set by the user — keep this target unless they asked to change it" : ""
              "- #{line.category.name} (#{line.category.group}): #{target}, spent #{whole(line.spent_cents)} so far this month#{hand}"
            end
            "The user already has these envelopes — propose the full set you'd " \
            "recommend now, keeping what works and adjusting what doesn't:\n#{rows.join("\n")}"
          end
      end

      def handle(response)
        body = response.dig("summary", "body")
        envelopes = parsed_envelopes(response.dig("budget", "categories"))
        raise Llm::Error, "The model didn't return a budget — try again." if envelopes.empty?

        applied = apply(envelopes)

        create_note(
          title: response.dig("summary", "title").presence || "Your budget, explained",
          body: [
            body.presence,
            envelope_block("Needs", applied, "needs"),
            envelope_block("Wants", applied, "wants"),
            envelope_block("Savings & debt", applied, "savings_debt"),
            envelope_block("Income", applied, "income"),
            provenance_footer
          ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
      end

      # Suggest-and-apply, D17 discipline: envelopes land, a hand-set target
      # is never overwritten, and every one of them is editable and
      # removable on the Budget page.
      def apply(envelopes)
        envelopes.each do |envelope|
          category = user.budget_categories.where("LOWER(name) = ?", envelope.name.downcase).first

          if category
            category.update!(archived_at: nil)
            next if category.target_hand_set?

            category.update!(group: envelope.group, monthly_target_cents: envelope.monthly_target_cents,
              target_set_by: "tool")
          else
            user.budget_categories.create!(name: envelope.name, group: envelope.group,
              monthly_target_cents: envelope.monthly_target_cents, target_set_by: "tool")
          end
        end
      end

      def parsed_envelopes(list)
        seen = Set.new

        Array(list).filter_map do |entry|
          next unless entry.is_a?(Hash)

          name = entry["name"].to_s.squish.first(60)
          next if name.blank? || seen.include?(name.downcase)

          cents = target_cents(entry["monthly_target"])
          next unless cents

          seen << name.downcase
          Envelope.new(
            name: name,
            group: entry["group"].to_s.presence_in(BudgetCategory::GROUPS) || "needs",
            monthly_target_cents: cents,
            why: entry["why"].to_s.strip.presence)
        end.first(MAX_CATEGORIES)
      end

      # Validated hard: numeric, non-negative, under a sanity ceiling.
      # Anything else is dropped rather than stored (the money equivalent
      # of the triage validation wall).
      def target_cents(value)
        return nil unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+(\.\d+)?\z/)

        cents = (value.to_f * 100).round
        cents if cents >= 0 && cents <= MAX_TARGET_CENTS
      end

      def envelope_block(heading, envelopes, group)
        rows = envelopes.select { |envelope| envelope.group == group }
        return nil if rows.none?

        lines = rows.map do |envelope|
          "- #{envelope.name}: #{whole(envelope.monthly_target_cents)}#{" — #{envelope.why}" if envelope.why}"
        end
        "#{heading}:\n#{lines.join("\n")}"
      end

      # Appended by code: where these numbers came from, so the note can
      # never overstate its own basis.
      def provenance_footer
        basis = if aggregates.any?
          "Built from #{aggregates.months_covered} #{"month".pluralize(aggregates.months_covered)} " \
          "of your imported spending" + (stated_anything? ? " and what you told us" : "")
        else
          "Built from what you told us — there's no imported spending yet, so treat these as starting points"
        end

        "#{basis}, on #{Date.current.strftime("%B %-d, %Y")}. Every envelope is yours to edit or " \
        "remove on the Budget page; a target you set by hand is never overwritten when you re-run this."
      end

      def stated_anything?
        inputs[:take_home].present? || inputs[:housing].present? || inputs[:situation].present?
      end

      def aggregates = @aggregates ||= Spending::Aggregates.new(user: user)

      def summary = @summary ||= Money::MonthSummary.new(user: user)

      def whole(cents) = "#{(cents / 100.0).round} #{user.household.currency}"

      def fallback_title = "Your budget, explained"
  end
end
