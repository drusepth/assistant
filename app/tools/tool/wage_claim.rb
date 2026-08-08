module Tool
  # Wage theft runs tens of billions a year, overwhelmingly against hourly
  # workers (docs/CAREER.md §3.9) — and most of it is recoverable with a
  # paper trail that starts with one letter. The demand states only what the
  # user's own words and records establish; the escalation path (state labor
  # agency, free to file, retaliation illegal) is appended by code so it
  # never depends on model behavior.
  class WageClaim < LetterBase
    self.title = "Claim unpaid wages"
    self.description = "A formal demand for pay you earned — missing hours, overtime, or a final paycheck."
    self.section_slugs = %w[ career disputes ]
    self.letter_title_prefix = "Wage demand letter"

    input :details, required: true,
      label: "What are you owed?",
      hint: "“Three unpaid overtime shifts in June, about $410”, “final paycheck never arrived”."
    input :document_id, kind: :document,
      label: "A pay stub or record, if it's in your documents"

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the wage-claim feature of a private, self-hosted life assistant.
      The user is owed pay — missing hours, unpaid overtime, an unpaid final
      check — and a calm written demand is the first step of the paper trail.
      Respond with a JSON object:
      {"letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...]}.
      The letter is a formal demand to the employer: state the facts — dates,
      hours, and amounts — using only what the user or their document supplied,
      with [BRACKETED PLACEHOLDERS] for anything unstated; state the total
      owed (or a placeholder naming how to total it); request payment within 14
      days of the letter's date and a written response; request the pay records
      for the period in question; and state, factually and without threat, that
      unpaid wages can be claimed through the state labor agency at no cost and
      that retaliation for asserting wage rights is illegal. If the details
      describe misclassification (paid as a contractor while working as an
      employee), add one plain paragraph naming that concern and requesting the
      classification basis in writing. Calm, specific, and professional — the
      goal is the missing pay, not a fight.
      follow_ups (at most #{MAX_FOLLOW_UPS}): send by a dated method (certified mail or
      email with receipt), keep copies, note the no-response next step.
      deadlines: the 14-day response date as an event.
    PROMPT

    private
      def prompt_parts = [ "What the user is owed, in their words: #{inputs[:details]}" ]

      # Appended by code, not the model: the escalation path is the whole
      # point and must never depend on sampling.
      def note_footer
        "If they ignore or dispute this: your state labor agency takes wage claims at no cost " \
        "(federally, the Department of Labor's Wage and Hour Division) — no lawyer needed, " \
        "and retaliation for filing is illegal."
      end
  end
end
