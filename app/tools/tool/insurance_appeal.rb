module Tool
  # Fewer than 1% of denied claims are ever appealed, though appeals often
  # succeed — the gap is expertise, nerve, and a tracked deadline, which is
  # exactly what a draft tool supplies. Reads the denial, drafts the formal
  # internal appeal, and puts the appeal window on the calendar where it
  # can't be lost.
  class InsuranceAppeal < LetterBase
    self.title = "Appeal an insurance denial"
    self.description = "Turn a denial letter or EOB into a formal appeal, with the deadline on your calendar."
    self.section_slugs = %w[ disputes health ]
    self.letter_title_prefix = "Appeal letter"

    input :document_id, kind: :document, required: true,
      label: "Which denial is this about?"
    input :intent,
      label: "Anything the appeal should stress?",
      hint: "Optional — “the ER visit was an emergency”, “my doctor says it was medically necessary”."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the insurance-appeal feature of a private, self-hosted life assistant.
      The user's insurance claim was denied and they want to appeal. Draft a formal
      internal appeal letter they can send to their insurer, and list what sending
      it implies. Respond with a JSON object:
      {"letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...]}.
      The letter must: identify the claim in the first paragraph (claim number,
      date of service, patient) and state that this is a formal appeal with the
      requested outcome; quote the insurer's stated denial reason verbatim when the
      document gives one, and rebut it with the facts available; request the plan
      language the denial relies on (the specific evidence-of-coverage provision);
      request a written decision within the plan's required timeframe; state that
      the user will pursue an independent external review if the internal appeal is
      denied; stay polite, specific, and unemotional; invent nothing — where a
      detail is unknown (member ID, plan name, the treating doctor), leave a
      [BRACKETED PLACEHOLDER] for the user to fill in.
      follow_ups are at most #{MAX_FOLLOW_UPS} small concrete actions (send by certified mail,
      request supporting records from the doctor, chase a reply), each completable
      in a day; due_on only for real dates, resolved against today.
      deadlines are the hard dates at stake — above all the appeal-filing deadline.
      Compute it from the document when it states a window; when it doesn't,
      include one titled "Appeal deadline — check your denial letter (plans
      commonly allow 180 days)" dated 150 days from today as a conservative
      reminder. At most #{MAX_DEADLINES}.
    PROMPT

    private
      def prompt_parts
        [ ("What the user wants the appeal to stress: #{inputs[:intent]}" if inputs[:intent].present?) ]
      end
  end
end
