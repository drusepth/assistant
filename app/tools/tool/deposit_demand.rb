module Tool
  # Security deposits go unrecovered because nobody sends the demand letter.
  # The lease or the landlord's deduction letter helps but isn't required —
  # one line of facts plus [BRACKETED PLACEHOLDERS] is enough to put a formal
  # demand in the user's hands. Tier-A honesty: state law sets the return
  # deadline and penalties, so the letter cites them as "commonly / verify
  # for your state" rather than asserting day-counts the model can't know
  # are current (Q11).
  class DepositDemand < LetterBase
    self.title = "Get my deposit back"
    self.description = "A formal demand for your security deposit, with the follow-through scheduled."
    self.section_slugs = %w[ disputes renting ]
    self.letter_title_prefix = "Deposit demand letter"

    input :details, required: true,
      label: "The basics",
      hint: "One line — “moved out June 30, $1,800 deposit, 12 Oak St, no itemized list yet”."
    input :document_id, kind: :document,
      label: "The lease or the landlord's letter, if it's in your documents"

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the deposit-recovery feature of a private, self-hosted life assistant.
      The user moved out of a rental and wants their security deposit back. Draft a
      formal demand letter to the landlord and list what sending it implies.
      Respond with a JSON object:
      {"letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...]}.
      The letter must: state in the first paragraph that it is a formal demand for
      return of the security deposit, naming the amount, the rental address, and
      the move-out date; provide a forwarding address line for payment (a
      [BRACKETED PLACEHOLDER] if unknown); demand the itemized statement of any
      deductions; note that state law sets a deadline for returning deposits and
      commonly allows penalties — up to a multiple of the deposit — when it is
      missed, phrased as "commonly" and "verify the rules for your state", never
      asserting a specific state's current day-count (even when the state is
      known, hedge with "verify"); set a firm response date roughly 14 days out;
      close with the intent to pursue small claims court if ignored. Stay polite,
      specific, and unemotional; invent nothing — unknown details get a
      [BRACKETED PLACEHOLDER].
      follow_ups are at most #{MAX_FOLLOW_UPS} concrete actions (send by certified mail, gather
      move-out photos and the lease, file in small claims if no response by the
      stated date). deadlines are at most #{MAX_DEADLINES}: the response date the letter sets,
      and nothing invented beyond the letter's own dates.
    PROMPT

    private
      def prompt_parts
        [ "The facts from the user: #{inputs[:details]}", region_line ]
      end
  end
end
