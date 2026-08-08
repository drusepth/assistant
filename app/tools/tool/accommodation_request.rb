module Tool
  # The formal accommodation request (docs/CAREER.md §3.9) — ADA, pregnancy,
  # or religious. The letter that starts the interactive process on the
  # record, saying enough to establish the need and no more: the
  # share-only-what's-needed line and the escalation path are appended by
  # code, never left to the model.
  class AccommodationRequest < LetterBase
    self.title = "Request an accommodation"
    self.description = "The formal ask — medical, pregnancy, or religious — that starts the process on the record."
    self.section_slugs = %w[ career rights ]
    self.letter_title_prefix = "Accommodation request"

    input :need, required: true,
      label: "What do you need, and why?",
      hint: "“A stool for my register shifts — standing all day aggravates a back injury”, “Fridays off before sundown”."
    input :document_id, kind: :document,
      label: "A doctor's note or policy, if it's in your documents"

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the accommodation-request feature of a private, self-hosted life
      assistant. The user needs a change at work — for a medical condition,
      pregnancy, or religious practice — and a written request is what starts
      the formal interactive process. Respond with a JSON object:
      {"letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...]}.
      The letter, addressed to the manager or HR:
      - States that this is a formal request for a reasonable accommodation.
      - Describes the limitation or practice in the user's own words — only
        what is needed to establish the need, never a full medical history;
        where medical documentation would help, offer it rather than attach
        the user's private details.
      - Names the specific accommodation requested, ties it to the job's
        actual duties, and states openness to discussing alternatives that
        meet the same need — the interactive process is the point.
      - Requests a written response by a reasonable stated date.
      Calm, cooperative, specific; [BRACKETED PLACEHOLDERS] for anything the
      user didn't supply. Never assert what the law requires in the user's
      jurisdiction — the letter requests, the footer names where rights get
      enforced.
      follow_ups (at most #{MAX_FOLLOW_UPS}): send with a dated record, keep a copy, note
      the response date.
      deadlines: the requested response date as an event.
    PROMPT

    private
      def prompt_parts = [ "What the user needs, in their words: #{inputs[:need]}" ]

      def note_footer
        "You don't have to share your full diagnosis or history — only enough to establish the need. " \
        "If the request is refused without any discussion of alternatives, the EEOC (or your state's " \
        "civil-rights agency) takes complaints at no cost, and retaliation for asking is illegal."
      end
  end
end
