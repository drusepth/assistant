module Tool
  # "Which one do I pay first?" (docs/MONEY.md §5.3) — a plan tool, so it
  # rides the shared breakdown pipeline with a rich brief and adds no
  # schema of its own. The honesty constraint is the whole design: the
  # model restates the user's own balances and rates, it does not perform
  # compound-interest theater, and it never recommends a credit product
  # (consolidation loans, balance transfers, refinancing) — that's the
  # D-money-coach boundary, and it applies just as hard here.
  class DebtPayoffPlan < Base
    self.title = "Make a debt payoff plan"
    self.description = "Your debts in one place, in the order that gets them gone."
    self.section_slugs = %w[ debt money ]
    self.kind = :plan

    METHODS = [
      "Avalanche — highest interest rate first (costs the least)",
      "Snowball — smallest balance first (feels the best)",
      "You pick for me"
    ].freeze

    input :debts, kind: :textarea, required: true,
      label: "What do you owe?",
      hint: "One per line, however you know it — “Visa 4,200 at 24%, min 95” or just “car loan, about 8k”."
    input :method, kind: :select, options: METHODS,
      label: "Which way do you want to work?"
    input :monthly_extra,
      label: "Roughly, what can you put toward debt each month beyond minimums?",
      hint: "Optional — even a small number changes the order of operations."

    BRIEF = <<~BRIEF.freeze
      This goal is paying off debt. Build a plan the person can actually follow
      for months, not a spreadsheet they'll abandon in week two.

      Structure the steps like this:
      - First, one step to write down every debt in one place with its balance,
        interest rate, minimum payment, and due date — most people have never
        seen them on one page, and the rest of the plan depends on it. If any
        rate or minimum is unknown, the step is to find it out (the statement,
        the portal, a phone call), not to guess.
      - Then the order of attack, using the method the user chose. If they asked
        you to pick: choose avalanche when the rates differ meaningfully, and
        snowball when the balances are small and close together or when the
        person sounds discouraged — and say in one sentence why you chose it.
        Explain both honestly: avalanche costs less in interest, snowball pays
        off a whole debt sooner, which is what keeps people going. Neither is
        the "right" one.
      - A step to make sure every minimum is on autopay, because a missed
        minimum undoes months of progress through fees and rate hikes.
      - The monthly rhythm: one recurring step for the extra payment against the
        current target debt, and one for a short monthly check of the balances.
      - A step to call about the worst rate. Rate reductions and hardship
        programs are real, free to ask about, and almost nobody asks.
      - Where it applies: a step to name the leak that created the debt, framed
        without blame — a category that's over every month, an emergency with no
        cushion. The app's spending review and budget can do this part.

      Hard rules:
      - Restate only the numbers the user gave you. Never invent a balance, a
        rate, or a payoff date, and never project a payoff month as if it were
        certain — "at this pace, roughly a year" is the ceiling, and only when
        their own numbers support it.
      - Never recommend a specific financial product: no consolidation loans, no
        balance transfer cards, no refinancing, no debt-settlement companies
        (which frequently make things worse). You may say in general terms that
        such options exist and that a nonprofit credit counselor — free or
        low-cost, NFCC-member in the US — is the person to ask.
      - If what they describe sounds like collections, a lawsuit, or wage
        garnishment, say plainly that this is a rights problem as much as a money
        problem, and that this app can draft a debt-validation response and track
        the deadlines. Do not improvise legal strategy.
      - No shame anywhere in the plan. Debt is a math problem with a feelings
        problem attached; treat both kindly.
    BRIEF

    def call
      plan_goal!(
        title: "Pay off my debt",
        description: description_from_inputs,
        brief: [ BRIEF, chosen_method, budget_note, region_line ].compact.join("\n\n")
      )
    end

    private
      def description_from_inputs
        parts = [ "What I owe:\n#{inputs[:debts]}" ]
        parts << "Extra toward debt each month: #{inputs[:monthly_extra]}" if inputs[:monthly_extra].present?
        parts.join("\n\n")
      end

      def chosen_method
        return "The user asked you to choose the method for them." if inputs[:method].blank? ||
          inputs[:method].to_s.start_with?("You pick")

        "The method the user chose: #{inputs[:method]}. Use it, and don't relitigate the choice."
      end

      # What the ledger already knows, so the plan can be concrete about
      # where the extra payment comes from — code-computed, never guessed.
      def budget_note
        summary = Money::MonthSummary.new(user: user)
        return nil unless summary.budgeted?

        planned = summary.group_target_cents("savings_debt")
        return nil unless planned&.positive?

        "Their budget already sets aside #{(planned / 100.0).round} #{user.household.currency} a month " \
        "for savings and debt — plan the extra payment against that number rather than inventing one."
      end
  end
end
