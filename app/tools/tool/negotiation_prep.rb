module Tool
  # The other side negotiates every day; most people accept the first
  # number. A prep sheet plus a send-ready counter-message evens the odds —
  # for a salary, a rent renewal, a bill. Tier-A honesty is the hard rule
  # here: the model never invents market rates or comparable prices; a
  # number the user didn't supply becomes a [BRACKETED PLACEHOLDER] telling
  # them exactly what to look up.
  class NegotiationPrep < Base
    self.title = "Prep me to negotiate"
    self.description = "Talking points, a script, your walkaway — and a counter-message ready to adapt."
    self.section_slugs = %w[ career renting bills ]
    self.kind = :draft

    input :scenario, required: true,
      label: "What are you negotiating?",
      hint: "“Salary offer from Acme”, “rent renewal asking +$150”, “internet bill went up”."
    input :constraints,
      label: "Your numbers and limits",
      hint: "Optional — “target $85k, current $72k”, “can't move before June”."
    input :document_id, kind: :document,
      label: "The offer, renewal notice, or bill, if it's in your documents"

    MAX_FOLLOW_UPS = 2

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the negotiation-prep feature of a private, self-hosted life
      assistant. The user is about to negotiate — a salary, a rent renewal, a
      bill — and the other side does this every day. Even the odds. Respond with
      a JSON object:
      {"prep": {"title": "...", "body": "..."},
       "counter_message": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The prep body is a one-page sheet: what each side wants; the user's
      leverage (from the provided facts only) and the other side's; an opening
      position with its reasoning; the walkaway point (from the user's stated
      limits, else a [BRACKETED PLACEHOLDER]); the three objections they will
      most likely hear, each with a calm reply; and a short script for the
      opening exchange.
      The counter_message is a separate, send-ready message making the counter
      politely and specifically — something the user can adapt and send.
      Use only numbers the user or the document supplied. Never invent market
      rates, comparable salaries, or competitor prices; where such a number
      would strengthen the case, leave a [BRACKETED PLACEHOLDER] naming exactly
      what to look up. Stay calm, specific, and collaborative in tone — the goal
      is a deal, not a fight.
      follow_ups: at most #{MAX_FOLLOW_UPS} (research a placeholder, send the counter by a
      date), with due_on resolved against today's date.
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The negotiation: #{inputs[:scenario]}"
        parts << "The user's numbers and limits: #{inputs[:constraints]}" if inputs[:constraints].present?
        if (document = chosen_document)
          parts << "The document (titled “#{document.title}”):\n#{document_text(document)}"
        end
        context = section_context
        parts << "Possibly relevant tracked data:\n#{context.to_prompt}" unless context.empty?
        parts.join("\n\n")
      end

      def filing_sources = [ chosen_document ]

      def handle(response)
        body = response.dig("prep", "body")
        raise Llm::Error, "The model didn't return a prep sheet — try again." if body.blank?

        create_note(
          title: response.dig("prep", "title").presence || "Negotiation prep — #{inputs[:scenario]}",
          body: body
        )
        if (counter = response.dig("counter_message", "body")).present?
          create_note(
            title: response.dig("counter_message", "title").presence || "Counter-offer draft — #{inputs[:scenario]}",
            body: counter
          )
        end
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
      end
  end
end
