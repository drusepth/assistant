module Tool
  # Subscription creep is the quiet leak in every budget, and companies
  # make the exit door hard to find on purpose. One note, two weapons: a
  # formal written cancellation (send it, keep a copy) and a short phone
  # script for the services that force a call — including how to decline
  # the retention offer without getting talked back in.
  class CancelSubscription < LetterBase
    self.title = "Cancel this subscription"
    self.description = "A written cancellation plus a phone script — and a reminder to check the next statement."
    self.section_slugs = %w[ subscriptions ]
    self.letter_title_prefix = "Cancellation request"

    input :service, required: true,
      label: "What are you canceling?",
      hint: "“Planet Gym membership”, “the streaming bundle”."
    input :details,
      label: "What you know",
      hint: "Optional — account email, when it renews, why you're leaving."
    input :document_id, kind: :document,
      label: "A bill or statement, if it's in your documents"

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the subscription-canceling feature of a private, self-hosted life
      assistant. The user wants out of a subscription; companies often make that
      deliberately hard. Draft the exit and list what it implies. Respond with a
      JSON object:
      {"letter": {"title": "...", "body": "..."},
       "script": "..." or null,
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...]}.
      The letter is a formal written cancellation the user can send or paste into
      a support form: state clearly that this is a cancellation request effective
      immediately (or by the renewal date when one is known); identify the account
      (name, account email, account or member number — [BRACKETED PLACEHOLDER]
      where unknown); request written confirmation of the cancellation and its
      effective date, and that billing stops; decline any retention offers in
      advance. Stay polite, specific, and unemotional; invent nothing.
      The script is for services that force a phone call or chat: a few short
      lines — the opening sentence, the one-line answer to "why are you
      leaving", and a firm polite decline for the retention offer ("no thank
      you, please just process the cancellation"), ending with asking for a
      confirmation number. Null when a written request is clearly enough.
      follow_ups are at most #{MAX_FOLLOW_UPS}: send or submit the cancellation, and always a
      check-the-next-statement task roughly a month out to catch continued
      charges. deadlines at most #{MAX_DEADLINES}: only a stated or clearly implied renewal
      or cancel-by date, resolved against today.
    PROMPT

    private
      def prompt_parts
        [
          "The subscription: #{inputs[:service]}",
          ("What the user knows: #{inputs[:details]}" if inputs[:details].present?)
        ]
      end

      def fallback_title = "#{self.class.letter_title_prefix} — #{inputs[:service]}"

      # The letter and the call script are one note — the user grabs
      # whichever exit the company allows.
      def handle(response)
        body = response.dig("letter", "body")
        raise Llm::Error, "The model didn't return a cancellation letter — try again." if body.blank?

        script = response["script"].to_s.strip.presence
        create_note(
          title: response.dig("letter", "title").presence || fallback_title,
          body: [ body, ("If you have to call:\n#{script}" if script) ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
        create_deadline_events(response["deadlines"])
      end
  end
end
