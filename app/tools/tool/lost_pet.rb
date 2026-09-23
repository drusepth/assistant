module Tool
  # The urgent one (D-pet-primitive), and the tool with the shortest useful
  # latency in the whole app: the first hours are when a lost animal is found,
  # and the owner is not in a state to plan. Everything it needs is already on
  # the record — her photo, her microchip number, her markings, where she
  # lives — so the sheet can be a checklist rather than a form.
  #
  # This is a draft tool rather than a chat on purpose. Someone standing in
  # the street wants a list they can work down, not a conversation.
  class LostPet < Base
    self.title = "My pet is missing"
    self.description = "The first-hour checklist, who to call, and a poster you can print."
    self.section_slugs = %w[ pets ]
    self.kind = :draft

    input :pet_id, kind: :pet, required: true, label: "Which pet?"
    input :last_seen,
      label: "Where and when were they last seen?",
      hint: "Optional — “back garden, about 4pm today”."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the lost-pet feature of a private, self-hosted life assistant.
      The user's animal is missing and they are frightened. Write a sheet they
      can work down, in this order:
      1. **The first hour** — the things that actually find animals, most
         effective first: search the house and immediate area thoroughly
         (frightened cats hide *inside*, close by, and silently), take a torch
         even in daylight, call the animal in a normal voice at dusk and
         dawn, and leave their bed, litter tray or a worn piece of clothing
         outside the door.
      2. **Who to call now** — the microchip registry (to flag the animal
         missing and confirm the contact details are current), local vets and
         emergency clinics, shelters and rescues, the council or animal
         warden, and any local lost-and-found groups. Say what to give each:
         microchip number, description, where and when last seen.
      3. **The poster and the posts** — what a poster must carry to work, and
         where to put them.
      4. **Over the next days** — what to keep doing, and what usually changes
         (many animals are found within a mile, and days later).
      Then, as a clearly separated final block headed "Poster text", write the
      poster itself: LOST, the name, species, breed, colour and distinguishing
      marks, where and when last seen, and a [PHONE NUMBER] placeholder — never
      invent a phone number, address or reward.
      Be calm, direct and specific. No reassurance that isn't true, and no
      speculation about what happened to the animal.
      The record says which pronoun the household uses for this pet. Use it
      throughout, and never guess a different one.
      follow_ups are the calls and posts, so they can be ticked off.
      #{DRAFT_FORMAT}
    PROMPT

    private
      def pet = @pet ||= chosen_pet

      def messages
        [ { role: "system", content: SYSTEM_PROMPT }, { role: "user", content: user_prompt } ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "Last seen: #{inputs[:last_seen]}" if inputs[:last_seen].present?
        parts << "The pet:\n#{poster_facts}"
        parts << "The household's region: #{region}" if region.present?
        parts.join("\n\n")
      end

      # The record's poster-relevant half, spelled out — a microchip number
      # buried in a general context block is the one fact that must not be
      # missed here.
      def poster_facts
        parts = [ "Name: #{pet.name}", "Species: #{pet.species_label}" ]
        parts << "Breed: #{pet.breed}" if pet.breed.present?
        parts << "Colour and markings: #{pet.color}" if pet.color.present?
        parts << "Sex: #{pet.sex_label}" if pet.sex_label
        parts << "Refer to this pet as: #{pet.pronouns.slashed}"
        parts << "Age: #{pet.age_phrase}" if pet.age_phrase
        parts << "Microchip number: #{pet.microchip}" if pet.microchip.present?
        parts << "MICROCHIP: not recorded in the app — tell the user to find the paperwork or ask their vet, " \
                 "who can look it up, and to check the registry's contact details are current." if pet.microchip.blank?
        parts << "Vet: #{pet.vet.name}#{" — #{PhoneNumber.format(pet.vet.phone)}" if pet.vet.phone.present?}" if pet.vet
        # A rabies tag traces back through the clinic that issued it — the
        # second way a finder or animal control can reach the owner.
        if (rabies = pet.pet_vaccinations.where(vaccine_key: "rabies").where.not(tag_number: [ nil, "" ]).chronological.first)
          parts << "Rabies tag number: #{rabies.tag_number}#{" (issued by #{rabies.given_by})" if rabies.given_by}"
        end
        parts << "Notes from the owner: #{pet.notes.truncate(500)}" if pet.notes.present?
        parts.join("\n")
      end

      def region = @region ||= user.household.region.presence

      def filing
        @pet_filing ||= (super + [ pet.section ]).uniq
      end

      def fallback_title = "#{pet.name} is missing — what to do now"
  end
end
