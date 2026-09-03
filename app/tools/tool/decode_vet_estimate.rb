module Tool
  # An itemized vet estimate, in plain language (D-pet-primitive). The
  # decode-letter move, pointed at the document that arrives at the worst
  # possible moment: a list of procedure codes and a number, handed to
  # someone in a waiting room deciding in five minutes.
  #
  # What it will not do is tell them whether to spend it. That decision
  # belongs to the owner and their vet, and a model that nudged it either way
  # — toward the money or away from it — would be doing something much worse
  # than being unhelpful.
  class DecodeVetEstimate < Base
    self.title = "Decode a vet estimate"
    self.description = "An itemized estimate in plain language, and the questions to ask before you agree."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :document_id, kind: :document, required: true, label: "Which estimate or invoice?"
    input :pet_id, kind: :pet, label: "Which pet?", hint: "Optional — lets the sheet read their record too."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the estimate-decoding feature of a private, self-hosted life
      assistant. The user has a veterinary estimate or invoice they don't
      fully understand. Write, in plain language a worried non-expert reads in
      a waiting room: what each line item actually is and why a vet would do
      it; which lines are the diagnostics, which are the treatment, and which
      are consumables or fees; what the total covers and what it explicitly
      doesn't (a low and high estimate usually means "if it's simple" and "if
      it isn't"); and the questions to ask before agreeing — what happens if we
      wait, what happens if we do only part of this, is there a staged version,
      what will you do if you find something else while they're under.
      Read only what the document states. Invent no prices, no procedures and
      no veterinary opinion; where a line is unreadable or ambiguous, say so
      and make it one of the questions.
      NEVER advise whether the treatment is worth the money, whether to
      proceed, or whether to consider euthanasia. That is the owner's decision
      with their vet, and your job is to make sure they understand what they
      are deciding.
      If the record shows pet insurance, add a short "before you pay" note:
      what to ask about direct billing and what the claim will need.
      follow_ups are practical (ask for the staged version in writing, check
      the policy's per-condition limit, photograph the itemized copy).
      #{DRAFT_FORMAT}
    PROMPT

    private
      def pet = @pet ||= chosen_pet

      def messages
        [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: user_prompt } ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The estimate:\n#{estimate_text}"
        parts << "The pet:\n#{pet_context(pet)}" if pet
        parts.join("\n\n")
      end

      def estimate_text
        document = chosen_document
        "Titled “#{document.title}”:\n#{document_text(document)}"
      end

      def filing_sources = [ chosen_document ]

      def filing
        @pet_filing ||= (super + [ pet&.section ].compact).uniq
      end

      def fallback_title = "Vet estimate, decoded"
  end
end
