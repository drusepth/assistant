module Tool
  # The money coach (D-money-coach, docs/MONEY.md §5.1) — the half a
  # spreadsheet can't ship: someone to talk to at the moment of
  # temptation, who knows your budget and your goals and answers without
  # judgment. Scoped hard as support, not financial advice (the D32
  # boundary translated): no investment, tax, or credit-product
  # recommendations, and the not-an-advisor notice is appended by code so
  # the guardrail never depends on model behavior. Debt distress steers to
  # nonprofit credit counseling and to the app's own letter tools — the
  # 988 pattern, translated: the heaviest moments route to humans and to
  # the things that actually stop harm.
  class MoneyCoach < ChatBase
    self.title = "Talk it through"
    self.description = "Thinking about buying something, or want to spend less? Talk it out with your own numbers."
    self.section_slugs = %w[ money budget ]
    self.quick_replies = [
      "I want to buy something",
      "Help me spend less",
      "I'm stressed about money",
      "Help me plan this month"
    ]

    input :about,
      label: "What's on your mind?",
      hint: "Optional — “thinking about a $400 espresso machine”, or just start talking."
    input :category_id, kind: :budget_category,
      label: "About a particular envelope?",
      hint: "Optional — pick one and the coach starts there."

    MAX_RECAPS = 3
    MAX_RECAP_CHARS = 400
    MAX_GOALS = 5

    ADVISOR_NOTICE = "This is budgeting support, not financial advice — I'm not a licensed " \
      "financial advisor, and for investment, tax, or legal decisions a professional is worth " \
      "the call. If debt is the problem, nonprofit credit counseling (in the US, an NFCC-member " \
      "agency) is free or low-cost and genuinely helps.".freeze

    BEHAVIOR = <<~PROMPT.freeze
      You are the money coach in a private, self-hosted life assistant. The person
      you're talking to owns this app and their data; you are on their side, always.
      Most people never get a money conversation that isn't a sales pitch — this is
      that conversation. Rules of the room:

      - Never shame, never moralize, never catastrophize. Curiosity over verdicts.
        You are not the budget police; you defend the user's OWN stated plan back
        to them, and that is the whole job.
      - Ask before telling. Short turns, plain conversational text — a dialogue,
        not a lecture, and never a wall of bullet points.
      - Use their real numbers, given to you below, and never invent one. If you
        don't know what something costs or what's left, ask.

      When they're thinking about buying something:
      - Find out what it is, what it costs, and which envelope it would come from.
      - Show the tradeoff in their own numbers: what it leaves in that envelope,
        and what it displaces — including any goal they've told you they're saving
        for. Ask what they'd be giving up, rather than announcing it.
      - Offer the 48-hour wait as a move they can choose, never as a rule you
        impose, and only once.
      - If they say they're buying it anyway: help them fit it in gracefully.
        Adjust the plan, find the room, and drop the subject — no lecture, no
        parting shot, no "are you sure". A coach who sulks gets closed and never
        reopened.

      When they want to spend less: work from the envelopes that are actually
      over, propose specific and small changes, and name what each is worth per
      month. Cutting a thing they love is a last resort, not a first.

      When they're stressed about money: listen first. Money stress is rarely
      only about money. Reflect it back, keep the numbers concrete and small, and
      find the one next thing that helps.

      Hard boundaries, non-negotiable:
      - You are NOT a financial advisor. Never recommend specific investments,
        securities, funds, crypto, tax strategies, or credit products (cards,
        loans, refinancing, consolidation, "just put it on the card"). You may
        explain in general terms how something works, then say plainly that the
        decision deserves a professional.
      - If debt collectors, a lawsuit, eviction, or "I can't make rent" comes up:
        say clearly that nonprofit credit counseling exists and is free or
        low-cost, and mention that this app can draft the response letters and
        track the deadlines — those tools are one click from here. Do not
        improvise legal strategy.
      - No inference about their character from how they spend. Describe, ask,
        propose. They decide.
    PROMPT

    # The one guardrail that must not depend on the model: the not-an-advisor
    # notice opens every session, rendered in the transcript but never sent
    # to the model (notices never are).
    def call
      run.tool_run_messages.create!(role: :notice, content: ADVISOR_NOTICE)
      super
    end

    private
      def system_prompt
        parts = [ BEHAVIOR ]
        parts << "Their budget right now (computed from their own ledger — these numbers are " \
                 "yours to use and theirs to trust):\n#{snapshot}" if snapshot
        parts << "The envelope they came here about: #{chosen_category.name}" if chosen_category
        parts << "What they said they wanted to talk about: #{inputs[:about]}" if inputs[:about].present?
        parts << goals_block if goals_block
        parts << recaps_block if recaps_block
        parts << region_line if region_line
        parts.compact.join("\n\n")
      end

      def opening_instruction
        if inputs[:about].present?
          "Open the session: greet them briefly and warmly, then start on what they said they " \
            "wanted to talk about — with one question, not advice. Two or three sentences."
        else
          "Open the session: a brief, warm greeting. If their budget shows something worth " \
            "noticing this month, mention it in one plain sentence without alarm. Then ask what's " \
            "on their mind — buying something, spending less, planning the month, or just " \
            "thinking out loud. Two or three sentences, no lists."
        end
      end

      def recap_instruction
        <<~TEXT
          The conversation is wrapping up. Respond with a JSON object
          {"recap": {"title": "...", "body": "..."}}.
          The body: what they were deciding, what they decided (or what's still
          open), the numbers that mattered, and anything to revisit. Write it for
          them to reread in a month — plain, short, no judgment, and no advice
          they didn't ask for. Title like "Decided to wait on the espresso
          machine" — the decision, not the topic.
        TEXT
      end

      def recap_fallback_title = "Money talk — #{Date.current.strftime("%B %-d")}"

      def snapshot
        return @snapshot if defined?(@snapshot)
        @snapshot = Money::Snapshot.new(user: user).to_prompt
      end

      def chosen_category
        return @chosen_category if defined?(@chosen_category)
        @chosen_category = user.budget_categories.find_by(id: inputs[:category_id])
      end

      # What they're saving toward — the tradeoff the buy-decision protocol
      # weighs against, in their own words.
      def goals_block
        return @goals_block if defined?(@goals_block)

        titles = user.goals.active.joins(:sections)
          .where(sections: { slug: %w[ money budget debt assets ] })
          .distinct.limit(MAX_GOALS).pluck(:title)
        @goals_block = ("What they're working toward with money:\n#{titles.map { |t| "- #{t}" }.join("\n")}" if titles.any?)
      end

      def recaps_block
        return @recaps_block if defined?(@recaps_block)

        listing = past_recaps.map { |note| "- #{note.title}: #{note.body.truncate(MAX_RECAP_CHARS)}" }
        @recaps_block = if listing.any?
          "Recaps of past money talks, newest first — continuity, not an agenda:\n#{listing.join("\n")}"
        end
      end

      def past_recaps
        @past_recaps ||= begin
          earlier = user.tool_runs.where(tool_slug: self.class.slug).where.not(id: run.id).select(:id)
          ToolRunItem.where(tool_run_id: earlier, item_type: "Note")
            .order(created_at: :desc, id: :desc).limit(MAX_RECAPS).filter_map(&:item)
        end
      end
  end
end
