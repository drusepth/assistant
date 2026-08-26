module Tool
  # A Situation (D7), and one of the clearest: bringing an animal home
  # touches Health, Money, People and the calendar in the first fortnight,
  # and the things people forget are the boring ones — updating the microchip
  # registry to *their* details, the second vaccination three weeks later,
  # the insurance waiting period that starts the day you buy rather than the
  # day you claim.
  #
  # It ships as a plan tool with a cross-section brief, which is the whole
  # point of the Situation idea: no new machinery, just a good brief.
  class NewPet < Base
    self.title = "Bringing a pet home"
    self.description = "The first fortnight as a plan — vet, microchip, supplies, budget, and settling in."
    self.section_slugs = %w[ people health ]
    self.kind = :plan

    input :name, required: true, label: "What's their name?"
    input :species, kind: :select, required: true, label: "What are they?",
      options: Pet::SPECIES.map { |slug| [ Pet::SPECIES_LABELS[slug], slug ] }
    input :arriving,
      label: "When are they arriving?",
      hint: "Optional — a date, or “next month”."
    input :details,
      label: "Anything else?",
      hint: "Optional — rescue or breeder, age, other pets in the house, kids, rented home…"

    BRIEF = <<~BRIEF.freeze
      This goal is bringing a new pet home — a Situation spanning several life
      areas, so spread the steps' sections rather than filing them all in one:
      - Health: register with a vet and book the first check within the first
        week; find out what vaccinations they've had and what is still due
        (a puppy or kitten course is more than one visit, weeks apart);
        neutering, flea and worm treatment, and the microchip.
      - Rights and admin (money/rights): update the microchip registry to the
        new owner's own details — the single most-forgotten step, and the one
        that decides whether a found pet comes back; licensing or registration
        where the household's region requires it; check the tenancy or lease
        if renting.
      - Money: the one-off kit (bed, crate, bowls, lead, carrier, litter),
        then the recurring line — food, preventative treatment, insurance.
        Insurance is worth deciding in the first days: waiting periods start
        at purchase, and anything that shows up first is pre-existing forever.
      - Home and routine: what to buy before they arrive, pet-proofing, the
        first-night plan, house-training or litter setup, and a settling-in
        routine that doesn't overwhelm them.
      - People: introducing existing pets and children slowly, and telling
        whoever will be feeding them when you're away.
      - Learning: for a dog, booking classes early is the difference between a
        habit and a problem.
      Schedule from the arrival date when one is given: what must be bought
      before, what happens in week one, what happens by week six. Include only
      what fits — a rescue adult cat needs a different fortnight than a puppy.
    BRIEF

    def call
      plan_goal!(title: "Bringing #{inputs[:name].to_s.strip} home", brief: BRIEF, description: description_text)
    end

    private
      def description_text
        parts = [ "#{inputs[:name]} — #{Pet::SPECIES_LABELS[inputs[:species]] || inputs[:species]}" ]
        parts << "Arriving: #{inputs[:arriving]}" if inputs[:arriving].present?
        parts << inputs[:details] if inputs[:details].present?
        parts.join("\n")
      end
  end
end
