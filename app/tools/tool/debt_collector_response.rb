module Tool
  # Most collection lawsuits end in default judgment because the person
  # never responds at all. The default posture is the FDCPA debt-validation
  # request — the 30-day validation window is the most valuable deadline in
  # the domain — and the letter never admits the debt or promises payment
  # unless the user's stance explicitly says settle. A court summons is a
  # different animal a letter cannot answer, so that warning is a fixed
  # footer appended by code, never left to model behavior.
  class DebtCollectorResponse < LetterBase
    self.title = "Answer a debt collector"
    self.description = "Demand validation in writing — or dispute the debt — before the 30-day window closes."
    self.section_slugs = %w[ disputes debt ]
    self.letter_title_prefix = "Debt collector response"

    input :document_id, kind: :document, required: true,
      label: "Which collection notice is this about?"
    input :stance,
      label: "Where do you stand?",
      hint: "Optional — “I don't recognize this debt”, “the amount is wrong”, “it's mine and I want to settle”."

    SUMMONS_FOOTER = <<~TEXT.strip.freeze
      —
      If what you received is a court summons rather than a collection letter, a
      response letter is not enough: you must file an answer with the court before
      the deadline it states. Answering — even simply — prevents an automatic
      default judgment.
    TEXT

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the debt-collector-response feature of a private, self-hosted life
      assistant. The user received a notice from a debt collector and wants to
      respond without harming their own position. Draft a formal response letter
      and list what sending it implies. Respond with a JSON object:
      {"letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...]}.
      Unless the user's stance says otherwise, the letter is a debt-validation
      request under the Fair Debt Collection Practices Act: identify the notice by
      its reference number and date; request written validation of the debt — the
      amount and how it was calculated, the original creditor, and proof the
      collector is entitled to collect it; state that all further communication
      must be in writing. If the stance disputes the debt or the amount, state the
      dispute plainly. The letter must never admit the debt, promise payment, or
      name amounts unless the stance explicitly asks to settle. Stay polite,
      specific, and unemotional; invent nothing — unknown details get a
      [BRACKETED PLACEHOLDER].
      The FDCPA validation window is 30 days from first contact: always include a
      deadline for sending this letter, computed as 30 days after the notice's date
      when the document states one, otherwise 30 days from today, titled
      "Validation request deadline — send the letter before this".
      If the document is actually a court summons or complaint, the letter instead
      becomes a short plain-language notice addressed to the user themselves: what
      the summons says, that they must file an answer with the court — a letter to
      the collector cannot substitute — and the court's answer deadline as a
      deadlines entry.
      follow_ups are at most #{MAX_FOLLOW_UPS} concrete actions (send by certified mail with
      return receipt, keep a copy with the notice, chase the validation reply);
      deadlines at most #{MAX_DEADLINES}.
    PROMPT

    private
      def prompt_parts
        [ ("The user's stance: #{inputs[:stance]}" if inputs[:stance].present?) ]
      end

      def note_footer = SUMMONS_FOOTER
  end
end
