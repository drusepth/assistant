module Tool
  # Two pet policies, side by side (D-pet-primitive). The compare-plans shape,
  # aimed at a market whose asymmetry is worse than human health cover: the
  # premium is the number on the front, and the exclusions are where the
  # money actually is — pre-existing conditions, hereditary and congenital
  # conditions, per-condition and annual caps, waiting periods, and whether
  # cover for a condition ends when the policy year does.
  class ComparePetInsurance < Base
    self.title = "Compare pet insurance"
    self.description = "Two policies side by side — the premium, and the exclusions that actually bite."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :policy_a_id, kind: :document, required: true, label: "First policy document"
    input :policy_b_id, kind: :document, required: true, label: "Second policy document"
    input :pet_id, kind: :pet, label: "Which pet?", hint: "Optional — their age and breed change which clauses matter."

    MAX_POLICY_CHARS = 9_000

    DISCLAIMER = "A comparison can only weigh what these documents say — the policy wording controls, " \
      "and quoted premiums usually rise as a pet ages. Confirm anything that decides it with the " \
      "insurer before buying. This organizes; it doesn't advise.".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the policy-comparison feature of a private, self-hosted life
      assistant. The user has two pet insurance documents and needs to choose.
      In short headed parts: summarize each policy plainly; then compare, side
      by side, only what the documents state — premium and excess, the annual
      or per-condition limit and whether it resets, reimbursement percentage,
      waiting periods, and above all the exclusions: pre-existing conditions
      and how each defines one, hereditary and congenital conditions, dental,
      behavioural, alternative therapy, and whether it is lifetime cover or
      cover that ends when the policy year does (the single most expensive
      difference between two pet policies, and the one buyers miss).
      Write a [BRACKETED PLACEHOLDER] naming what to look up wherever a
      document is silent. Never guess a number.
      Then reason through the scenarios that fit this pet: one bad year, one
      chronic condition diagnosed at five and treated for life, and an old age.
      End with the questions to ask the insurer before buying.
      #{DRAFT_FORMAT}
      follow_ups are small concrete actions ("ask whether the pet's existing skin
      condition counts as pre-existing", "check the per-condition cap").
    PROMPT

    private
      def pet = @pet ||= chosen_pet

      def messages
        [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: user_prompt } ]
      end

      def user_prompt
        if policy_a.id == policy_b.id
          raise Llm::Error, "Those are the same document — pick two different policies to compare."
        end

        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The pet:\n#{pet_context(pet)}" if pet
        parts << "Policy A (titled “#{policy_a.title}”):\n#{document_text(policy_a).truncate(MAX_POLICY_CHARS)}"
        parts << "Policy B (titled “#{policy_b.title}”):\n#{document_text(policy_b).truncate(MAX_POLICY_CHARS)}"
        parts.join("\n\n")
      end

      def policy_a = chosen_document(:policy_a_id)
      def policy_b = chosen_document(:policy_b_id)

      def filing_sources = [ policy_a, policy_b ]

      def filing
        @pet_filing ||= (super + [ pet&.section ].compact).uniq
      end

      def handle(response)
        body = response.dig("draft", "body")
        raise Llm::Error, "The model didn't return a comparison — try again." if body.blank?

        create_note(
          title: response.dig("draft", "title").presence || fallback_title,
          body: [ body, DISCLAIMER ].join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
      end

      def fallback_title = "Compared — #{policy_a.title} vs. #{policy_b.title}"
  end
end
