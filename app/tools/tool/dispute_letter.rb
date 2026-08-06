module Tool
  # The first tool (M2.1) and the mission's heart: turn a bill, a denial, or
  # a collection notice into a formal dispute letter the user can send, plus
  # the follow-up steps sending it implies. Tier A (D19): reads only what's
  # already in the vault — no web capability assumed. The generic fallback of
  # the letter family — its specialized cousins are insurance_appeal,
  # debt_collector_response, and deposit_demand.
  class DisputeLetter < LetterBase
    self.title = "Draft a dispute letter"
    self.description = "Turn a bill, denial, or collection notice into a formal letter you can send."
    self.section_slugs = %w[ disputes ]
    self.letter_title_prefix = "Dispute letter"

    input :document_id, kind: :document, required: true,
      label: "Which document is this about?"
    input :intent,
      label: "What outcome do you want?",
      hint: "One line — “this charge is wrong, remove it”, “approve the claim”."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the dispute-letter feature of a private, self-hosted life assistant.
      The user has a document — a bill, a denial, a collection notice — they want
      to push back on. Draft a firm, factual, formal letter they can send, and list
      the follow-up steps sending it implies. Respond with a JSON object:
      {"letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The letter must: state the dispute and the requested outcome in the first
      paragraph; cite dates, amounts, and reference numbers from the document when
      present; request written confirmation and a response deadline; stay polite,
      specific, and unemotional; invent nothing — where a detail is unknown, leave
      a [BRACKETED PLACEHOLDER] for the user to fill in.
      follow_ups are at most #{MAX_FOLLOW_UPS} small concrete actions (send the letter, chase a
      reply, gather a missing record), each completable in a day; set due_on only
      when the document states or clearly implies a deadline, resolved against
      today's date.
    PROMPT

    private
      def prompt_parts
        [ ("What the user wants: #{inputs[:intent]}" if inputs[:intent].present?) ]
      end
  end
end
