module Tool
  # Doctor-visit prep, for the patient who can't describe the symptom
  # (D-pet-primitive). Same shape as its human twin and the same scope line:
  # preparation and comprehension, never diagnosis. The sheet's real content
  # is the *diet history* and the timeline — the two things an owner is
  # always asked for and never has to hand.
  class VetVisitPrep < Base
    self.title = "Prep for a vet visit"
    self.description = "The questions to ask, and the history the vet will ask you for."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :pet_id, kind: :pet, required: true, label: "Which pet?"
    input :reason,
      label: "What's the visit about?",
      hint: "Optional — “annual check”, “limping since Tuesday”, “she's off her food”."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the vet-visit prep feature of a private, self-hosted life
      assistant. From the pet's own record below, write a sheet the owner can
      bring to an appointment, in three parts: questions worth asking the vet;
      a brief history in plain language (what she eats and since when, current
      medications, the care on the calendar, anything the owner has noted); and
      what the vet will probably ask that the owner should work out before
      going — when it started, how often, what changed around it, whether she
      is eating, drinking, toileting and moving normally.
      You prepare and organize. You NEVER diagnose, never name a suspected
      condition, never suggest a medication or a dose. Questions are for the
      vet to answer.
      If the record names a symptom that sounds urgent (collapse, laboured
      breathing, a swollen belly, repeated unproductive retching, straining to
      urinate, seizures, suspected poisoning), open the sheet by saying plainly
      that this is a same-day call, not a prep sheet.
      follow_ups are practical (weigh her, photograph the label, bring the
      vaccination record).
      #{DRAFT_FORMAT}
    PROMPT

    private
      def pet = @pet ||= chosen_pet

      def messages
        [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: user_prompt } ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "What the visit is about: #{inputs[:reason]}" if inputs[:reason].present?
        parts << "The pet:\n#{pet_context(pet)}"
        papers = Pets::Papers.for(pet, user, limit: 6)
          .map { |document| "- #{[ document.title, document.summary&.truncate(300) ].compact.join(" — ")}" }
        parts << "Her papers:\n#{papers.join("\n")}" if papers.any?
        parts.join("\n\n")
      end

      def filing
        @pet_filing ||= (super + [ pet.section ]).uniq
      end

      def fallback_title = "#{pet.name} — vet visit prep"
  end
end
